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
    var selectedTV: TV? {
        didSet { if oldValue != selectedTV { Task { await loadInputSources() } } }
    }

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

    func changeToken() {
        status = .needsToken(reason: nil)
    }

    func press(_ key: RemoteKey) {
        send(key.command)
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

    private func loadInputSources() async {
        guard let tv = selectedTV else {
            inputSources = []
            return
        }
        inputSources = (try? await controller.inputSources(of: tv)) ?? []
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
