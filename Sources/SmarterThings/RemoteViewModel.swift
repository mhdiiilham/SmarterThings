import Foundation
import Observation
import SmarterThingsCore

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
    /// Short-lived message about a failed command; the remote stays usable.
    private(set) var notice: String?

    private let controller: TVController
    private let keyDispatcher: KeyDispatcher
    private let tokenStore: TokenStore
    private var noticeDismissal: Task<Void, Never>?

    init(controller: TVController, keyDispatcher: KeyDispatcher, tokenStore: TokenStore) {
        self.controller = controller
        self.keyDispatcher = keyDispatcher
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

    /// For reopening the popover: reload everything only the first time, otherwise just
    /// re-read the TV's state. SmartThings rate-limits, so this avoids needless calls.
    func loadIfNeeded() async {
        if status == .ready, selectedTV != nil {
            await loadSelectedTVState()
        } else {
            await load()
        }
    }

    func saveToken(_ token: String) async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        do {
            try tokenStore.save(trimmedToken)
            await load()
        } catch {
            status = .failed("Couldn't save the token to ~/Library/Application Support/SmarterThings.")
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

    /// Routed by KeyDispatcher: D-pad and volume go local when possible, the rest via cloud.
    func press(_ key: RemoteKey) {
        guard let tv = selectedTV else { return }
        Task {
            do {
                try await keyDispatcher.press(key, on: tv)
            } catch {
                showCommandFailure(error)
            }
        }
    }

    /// When the state is unknown, turn on: harmless if the TV is already on.
    func togglePower() {
        let wasPoweredOn = isPoweredOn
        let isTurningOff = wasPoweredOn == true
        isPoweredOn = !isTurningOff
        send(isTurningOff ? RemoteKey.powerOff.command : RemoteKey.powerOn.command) { [weak self] in
            self?.isPoweredOn = wasPoweredOn
        }
    }

    func toggleMute() {
        isMuted.toggle()
        send(isMuted ? RemoteKey.mute.command : RemoteKey.unmute.command) { [weak self] in
            self?.isMuted.toggle()
        }
    }

    func selectInput(_ source: InputSource) {
        guard let command = selectedTV?.selectInputCommand(source) else { return }
        send(command)
    }

    func launch(_ app: TVApp) {
        send(.launch(app))
    }

    /// Throws so the search field can show its own result instead of replacing the remote.
    func search(_ query: String) async throws {
        guard let tv = selectedTV else { return }
        try await controller.send(.search(query), to: tv)
    }

    var canLaunchApps: Bool { selectedTV?.canLaunchApps ?? false }
    var canSearch: Bool { selectedTV?.canSearch ?? false }

    func supports(_ key: RemoteKey) -> Bool {
        selectedTV?.supports(key) ?? false
    }

    /// `undo` reverts an optimistic UI change (power, mute) when the command fails.
    private func send(_ command: TVCommand, undo: (() -> Void)? = nil) {
        guard let tv = selectedTV else { return }
        Task {
            do {
                try await controller.send(command, to: tv)
            } catch {
                undo?()
                showCommandFailure(error)
            }
        }
    }

    private func showCommandFailure(_ error: Error) {
        switch error {
        case RemoteError.missingToken, RemoteError.tokenExpired:
            show(error)
        case RemoteError.rateLimited(let retryAfter):
            showNotice(Self.rateLimitMessage(retryAfter), for: .seconds(min(retryAfter ?? 5, 15)))
        case RemoteError.requestFailed(let statusCode):
            showNotice("Command failed (SmartThings HTTP \(statusCode)).", for: .seconds(4))
        default:
            showNotice(error.localizedDescription, for: .seconds(4))
        }
    }

    private func showNotice(_ message: String, for duration: Duration) {
        notice = message
        noticeDismissal?.cancel()
        noticeDismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private static func rateLimitMessage(_ retryAfter: Int?) -> String {
        let wait = retryAfter.map { "in \($0)s" } ?? "in a moment"
        return "SmartThings allows 12 commands a minute per TV. Try again \(wait)."
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
        case RemoteError.rateLimited(let retryAfter):
            status = .failed(Self.rateLimitMessage(retryAfter))
        case RemoteError.requestFailed(let statusCode):
            status = .failed("SmartThings returned HTTP \(statusCode).")
        default:
            status = .failed(error.localizedDescription)
        }
    }
}
