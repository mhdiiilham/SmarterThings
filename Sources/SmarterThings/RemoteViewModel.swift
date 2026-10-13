import Foundation
import Observation
import OSLog
import SmarterThingsCore

private let keyLog = Logger(subsystem: "com.mhdiiilham.SmarterThings", category: "keys")

/// The remote works over Wi-Fi with no SmartThings token. A token is optional: it adds
/// TV search, named input sources and cloud fallbacks (e.g. away from home).
@MainActor
@Observable
final class RemoteViewModel {
    enum Status: Equatable {
        case searching
        case ready
        case noTVFound
    }

    private(set) var status: Status = .searching
    /// The SmartThings TV matching the local one; `nil` without a token.
    private(set) var cloudTV: TV?
    private(set) var hasToken: Bool
    private(set) var inputSources: [InputSource] = []
    private(set) var isMuted = false
    /// `nil` while unknown.
    private(set) var isPoweredOn: Bool?
    /// A power change is in progress; further clicks are ignored until it settles.
    private(set) var isChangingPower = false
    /// Short-lived message about a failed command; the remote stays usable.
    private(set) var notice: String?
    var isEditingToken = false

    private let localTVs: LocalTVPickerViewModel
    private let controller: TVController
    private let keyDispatcher: KeyDispatcher
    private let appLauncher: AppLauncher
    private let power: PowerControl
    private let tokenStore: TokenStore
    private var noticeDismissal: Task<Void, Never>?

    init(
        localTVs: LocalTVPickerViewModel,
        controller: TVController,
        keyDispatcher: KeyDispatcher,
        appLauncher: AppLauncher,
        power: PowerControl,
        tokenStore: TokenStore
    ) {
        self.localTVs = localTVs
        self.controller = controller
        self.keyDispatcher = keyDispatcher
        self.appLauncher = appLauncher
        self.power = power
        self.tokenStore = tokenStore
        hasToken = tokenStore.token() != nil
    }

    var tvName: String { localTVs.activeDevice?.name ?? cloudTV?.name ?? "TV" }
    var connectionLabel: String { cloudTV == nil ? "Wi-Fi" : "Wi-Fi + SmartThings" }

    func load() async {
        status = .searching
        await localTVs.searchIfNeeded()
        await loadCloudTV()
        status = localTVs.activeDevice != nil || cloudTV != nil ? .ready : .noTVFound
        await refreshState()
    }

    /// Reopening the popover only re-reads the TV's state.
    func loadIfNeeded() async {
        if status == .ready {
            await refreshState()
        } else {
            await load()
        }
    }

    func searchAgain() async {
        await localTVs.search()
        await load()
    }

    // MARK: SmartThings (optional)

    func saveToken(_ token: String) async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        do {
            try tokenStore.save(trimmedToken)
            isEditingToken = false
            await load()
        } catch {
            showNotice("Couldn't save the token to ~/Library/Application Support/SmarterThings.", for: .seconds(5))
        }
    }

    func removeToken() {
        try? tokenStore.clear()
        hasToken = false
        cloudTV = nil
        inputSources = []
        isEditingToken = false
    }

    private func loadCloudTV() async {
        hasToken = tokenStore.token() != nil
        guard hasToken else {
            cloudTV = nil
            return
        }
        do {
            let televisions = try await controller.televisions()
            let localName = localTVs.activeDevice?.name
            cloudTV = televisions.first { $0.name == localName } ?? televisions.first
        } catch {
            cloudTV = nil
            if case RemoteError.tokenExpired = error {
                showNotice("SmartThings token expired; Wi-Fi control still works. Use the key button to update it.", for: .seconds(8))
            }
        }
    }

    private func refreshState() async {
        let tv = cloudTV
        async let poweredOn = power.isPoweredOn(cloudTV: tv)
        if let tv {
            inputSources = (try? await controller.inputSources(of: tv)) ?? []
        } else {
            inputSources = []
        }
        isPoweredOn = await poweredOn
    }

    // MARK: Commands

    /// Keys go over Wi-Fi; SmartThings is only a fallback when a token exists.
    /// Each press is logged with its route and duration (subsystem com.mhdiiilham.SmarterThings).
    func press(_ key: RemoteKey) {
        let tv = cloudTV
        Task {
            let start = ContinuousClock.now
            do {
                let route = try await keyDispatcher.press(key, on: tv)
                let elapsed = start.duration(to: .now)
                keyLog.notice("\(String(describing: key), privacy: .public) via \(route.rawValue, privacy: .public) in \(elapsed.milliseconds, privacy: .public) ms")
            } catch {
                keyLog.error("\(String(describing: key), privacy: .public) failed: \(String(describing: error), privacy: .public)")
                showCommandFailure(error)
            }
        }
    }

    /// Opens the direct TV connection when the remote appears, so the first press is instant.
    func warmUpLocalKeys() async {
        await keyDispatcher.warmUp()
    }

    /// Asks the TV for its current state first (the icon may be stale, e.g. after using the
    /// physical remote), then turns it off with `KEY_POWER` or on with Wake-on-LAN.
    /// The TV takes a few seconds to change, so the state is read again afterwards.
    func togglePower() {
        guard !isChangingPower else { return }
        isChangingPower = true
        let tv = cloudTV
        Task {
            defer { isChangingPower = false }
            do {
                isPoweredOn = try await power.toggle(cloudTV: tv)
            } catch {
                showCommandFailure(error)
            }
            try? await Task.sleep(for: .seconds(6))
            isPoweredOn = await power.isPoweredOn(cloudTV: cloudTV)
        }
    }

    /// Keeps the power icon in sync while the remote is open (e.g. TV turned off with its
    /// own remote). Runs until the calling task is cancelled, i.e. the popover closes.
    func watchPowerState(every interval: Duration = .seconds(10)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, status == .ready, !isChangingPower else { continue }
            isPoweredOn = await power.isPoweredOn(cloudTV: cloudTV)
        }
    }

    /// Locally `KEY_MUTE` toggles; the icon tracks presses since the TV doesn't report mute.
    func toggleMute() {
        isMuted.toggle()
        press(isMuted ? .mute : .unmute)
    }

    func selectInput(_ source: InputSource) {
        guard let tv = cloudTV, let command = tv.selectInputCommand(source) else { return }
        Task {
            do {
                try await controller.send(command, to: tv)
            } catch {
                showCommandFailure(error)
            }
        }
    }

    func launch(_ app: TVApp) {
        let tv = cloudTV
        Task {
            do {
                try await appLauncher.open(app, cloudTV: tv)
            } catch {
                showCommandFailure(error)
            }
        }
    }

    /// TV-wide search only exists in SmartThings. Throws so the search field shows its own result.
    func search(_ query: String) async throws {
        guard let tv = cloudTV else { return }
        try await controller.send(.search(query), to: tv)
    }

    /// Apps open over Wi-Fi, so shortcuts need no token.
    var canLaunchApps: Bool { status == .ready }
    var canSearch: Bool { cloudTV?.canSearch ?? false }

    /// Every key works over Wi-Fi; away from home, the SmartThings TV's capabilities decide.
    func supports(_ key: RemoteKey) -> Bool {
        if localTVs.activeDevice != nil { return true }
        return cloudTV?.supports(key) ?? false
    }

    // MARK: Notices

    private func showCommandFailure(_ error: Error) {
        switch error {
        case LocalTVError.tvNotFound:
            showNotice("Can't reach the TV on this Wi-Fi.", for: .seconds(4))
        case LocalTVError.accessDenied:
            showNotice("The TV blocked this Mac. Allow \"SmarterThings (Mac)\" on the TV.", for: .seconds(6))
        case LocalTVError.noResponse:
            showNotice("The TV didn't respond. If it's asking to allow this Mac, choose Allow.", for: .seconds(5))
        case WakeOnLAN.Failure.invalidMACAddress:
            showNotice("Can't turn the TV on yet: open SmarterThings once while the TV is on.", for: .seconds(6))
        case RemoteError.tokenExpired:
            showNotice("SmartThings token expired. Use the key button to update it.", for: .seconds(6))
        case RemoteError.rateLimited(let retryAfter):
            showNotice(Self.rateLimitMessage(retryAfter), for: .seconds(min(retryAfter ?? 5, 15)))
        case RemoteError.requestFailed(let statusCode):
            showNotice("Command failed (HTTP \(statusCode)).", for: .seconds(4))
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
}

private extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
