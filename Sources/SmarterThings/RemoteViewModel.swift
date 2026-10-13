import Foundation
import Observation
import OSLog
import SmarterThingsCore

private let keyLog = Logger(subsystem: "com.mhdiiilham.SmarterThings", category: "keys")

/// Everything goes straight to the TV over Wi-Fi; no account or token.
@MainActor
@Observable
final class RemoteViewModel {
    enum Status: Equatable {
        case searching
        case ready
        case noTVFound
    }

    private(set) var status: Status = .searching
    private(set) var isMuted = false
    /// `nil` while unknown.
    private(set) var isPoweredOn: Bool?
    /// A power change is in progress; further clicks are ignored until it settles.
    private(set) var isChangingPower = false
    /// Short-lived message about a failed command; the remote stays usable.
    private(set) var notice: String?

    private let localTVs: LocalTVPickerViewModel
    private let keys: TVKeyPresser
    private let apps: TVAppOpener
    private let power: PowerControl
    private var noticeDismissal: Task<Void, Never>?

    init(localTVs: LocalTVPickerViewModel, keys: TVKeyPresser, apps: TVAppOpener, power: PowerControl) {
        self.localTVs = localTVs
        self.keys = keys
        self.apps = apps
        self.power = power
    }

    var tvName: String { localTVs.activeDevice?.name ?? "TV" }

    func load() async {
        status = .searching
        await localTVs.searchIfNeeded()
        status = localTVs.activeDevice != nil ? .ready : .noTVFound
        await refreshPowerState()
    }

    /// Reopening the popover only re-reads the TV's state.
    func loadIfNeeded() async {
        if status == .ready {
            await refreshPowerState()
        } else {
            await load()
        }
    }

    func searchAgain() async {
        await localTVs.search()
        await load()
    }

    private func refreshPowerState() async {
        isPoweredOn = await power.isPoweredOn()
    }

    // MARK: Commands

    /// Each press is logged with its duration (subsystem com.mhdiiilham.SmarterThings, category keys).
    func press(_ key: RemoteKey) {
        Task {
            let start = ContinuousClock.now
            do {
                try await keys.press(key)
                keyLog.notice("\(String(describing: key), privacy: .public) in \(start.duration(to: .now).milliseconds, privacy: .public) ms")
            } catch {
                keyLog.error("\(String(describing: key), privacy: .public) failed: \(String(describing: error), privacy: .public)")
                showCommandFailure(error)
            }
        }
    }

    /// Opens the TV connection when the remote appears, so the first press is instant.
    func warmUpConnection() async {
        try? await keys.prepare()
    }

    /// Asks the TV for its current state first (the icon may be stale, e.g. after using the
    /// physical remote), then toggles it (see `PowerControl`). The spinner covers only the
    /// command; the TV takes a few seconds to change, so the state is read again later.
    func togglePower() {
        guard !isChangingPower else { return }
        isChangingPower = true
        Task {
            do {
                isPoweredOn = try await power.toggle()
            } catch {
                showCommandFailure(error)
            }
            isChangingPower = false
            try? await Task.sleep(for: .seconds(6))
            guard !isChangingPower else { return }
            isPoweredOn = await power.isPoweredOn()
        }
    }

    /// Keeps the power icon in sync while the remote is open (e.g. TV turned off with its
    /// own remote). Runs until the calling task is cancelled, i.e. the popover closes.
    func watchPowerState(every interval: Duration = .seconds(10)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, status == .ready, !isChangingPower else { continue }
            isPoweredOn = await power.isPoweredOn()
        }
    }

    /// `KEY_MUTE` toggles; the icon tracks presses since the TV doesn't report mute.
    func toggleMute() {
        isMuted.toggle()
        press(isMuted ? .mute : .unmute)
    }

    func launch(_ app: TVApp) {
        Task {
            do {
                try await apps.open(app)
            } catch {
                showCommandFailure(error)
            }
        }
    }

    var canLaunchApps: Bool { status == .ready }

    // MARK: Notices

    private func showCommandFailure(_ error: Error) {
        switch error {
        case LocalTVError.tvNotFound:
            showNotice("Can't reach the TV on this Wi-Fi.", for: .seconds(4))
        case LocalTVError.accessDenied:
            showNotice("The TV blocked this Mac. Allow \"SmarterThings (Mac)\" on the TV.", for: .seconds(6))
        case LocalTVError.noResponse:
            showNotice("The TV didn't respond. If it's asking to allow this Mac, choose Allow.", for: .seconds(5))
        case LocalTVError.requestFailed(404):
            showNotice("That app isn't installed on the TV.", for: .seconds(4))
        case WakeOnLAN.Failure.invalidMACAddress:
            showNotice("Can't turn the TV on yet: open SmarterThings once while the TV is on.", for: .seconds(6))
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
}

private extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
