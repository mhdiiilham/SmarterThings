import Foundation
import Observation
import TVRemoteCore

@MainActor
@Observable
final class RemoteViewModel {
    enum Status: Equatable {
        case needsToken(reason: String?)
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .loading
    private(set) var televisions: [TV] = []
    private(set) var inputSources: [InputSource] = []
    private(set) var isMuted = false
    /// `nil` until SmartThings reports the TV's switch state.
    private(set) var isPoweredOn: Bool?
    private(set) var selectedTV: TV?

    private let controller: TVController
    private let tokenStore: TokenStore

    init(controller: TVController, tokenStore: TokenStore) {
        self.controller = controller
        self.tokenStore = tokenStore
    }

    func load() async {
        guard tokenStore.token() != nil else {
            status = .needsToken(reason: nil)
            return
        }
        status = .loading
        do {
            televisions = try await controller.televisions()
            selectedTV = televisions.first { $0.id == selectedTV?.id } ?? televisions.first
            status = televisions.isEmpty ? .failed("No Samsung TV found in your SmartThings account.") : .ready
            await loadSelectedTVState()
        } catch {
            show(error)
        }
    }

    func saveToken(_ token: String) async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        do {
            try tokenStore.save(trimmedToken)
            await load()
        } catch {
            status = .failed("Couldn't save the token to the Keychain.")
        }
    }

    func select(_ tv: TV?) {
        guard tv != selectedTV else { return }
        selectedTV = tv
        Task { await loadSelectedTVState() }
    }

    func changeToken() {
        status = .needsToken(reason: nil)
    }

    func press(_ key: RemoteKey) {
        send(key.command)
    }

    /// When the state is unknown, turn on: harmless if the TV is already on.
    func togglePower() {
        let isTurningOff = isPoweredOn == true
        isPoweredOn = !isTurningOff
        press(isTurningOff ? .powerOff : .powerOn)
    }

    func toggleMute() {
        isMuted.toggle()
        press(isMuted ? .mute : .unmute)
    }

    func selectInput(_ source: InputSource) {
        guard let command = selectedTV?.selectInputCommand(source) else { return }
        send(command)
    }

    func supports(_ key: RemoteKey) -> Bool {
        selectedTV?.supports(key) ?? false
    }

    private func send(_ command: TVCommand) {
        guard let tv = selectedTV else { return }
        Task {
            do {
                try await controller.send(command, to: tv)
            } catch {
                show(error)
            }
        }
    }

    private func loadSelectedTVState() async {
        guard let tv = selectedTV else {
            inputSources = []
            isPoweredOn = nil
            return
        }
        async let sources = try? controller.inputSources(of: tv)
        async let poweredOn = try? controller.isPoweredOn(tv)
        inputSources = await sources ?? []
        isPoweredOn = await poweredOn
    }

    private func show(_ error: Error) {
        switch error {
        case RemoteError.missingToken:
            status = .needsToken(reason: nil)
        case RemoteError.tokenExpired:
            status = .needsToken(reason: "Your token expired or was revoked. Paste a new one.")
        case RemoteError.requestFailed(let statusCode):
            status = .failed("SmartThings returned HTTP \(statusCode).")
        default:
            status = .failed(error.localizedDescription)
        }
    }
}
