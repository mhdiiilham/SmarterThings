/// Power without the cloud. The TV reports its own state:
/// - on: `KEY_POWER` turns it off
/// - standby: it's still listening, so `KEY_POWER` turns it on
/// - unreachable: Wake-on-LAN, plus SmartThings `switch.on` when a token exists
/// `KEY_POWER` is a toggle, so every decision is made from a fresh reading.
public struct PowerControl: Sendable {
    private let keys: KeyDispatcher
    private let cloud: TVController
    private let localPowerState: @Sendable () async -> TVPowerState
    private let wake: @Sendable () async throws -> Void

    /// `wake` sends Wake-on-LAN, throwing if the TV's MAC address isn't known yet.
    public init(
        keys: KeyDispatcher,
        cloud: TVController,
        localPowerState: @escaping @Sendable () async -> TVPowerState,
        wake: @escaping @Sendable () async throws -> Void
    ) {
        self.keys = keys
        self.cloud = cloud
        self.localPowerState = localPowerState
        self.wake = wake
    }

    /// `nil` when unknown. A TV that doesn't answer locally and has no cloud is treated as off.
    public func isPoweredOn(cloudTV: TV?) async -> Bool? {
        switch await localPowerState() {
        case .on: return true
        case .standby: return false
        case .unreachable:
            guard let cloudTV else { return false }
            return try? await cloud.isPoweredOn(cloudTV)
        }
    }

    /// Returns the new power state.
    @discardableResult
    public func toggle(cloudTV: TV?) async throws -> Bool {
        switch await localPowerState() {
        case .on:
            try await pressPowerKey()
            return false
        case .standby:
            try await pressPowerKey()
            return true
        case .unreachable:
            if let cloudTV, (try? await cloud.isPoweredOn(cloudTV)) == true {
                try await cloud.send(RemoteKey.powerOff.command, to: cloudTV)
                return false
            }
            try await wakeFromDeepStandby(cloudTV: cloudTV)
            return true
        }
    }

    /// `KEY_POWER` over the local connection only: a cloud fallback would send an explicit
    /// on/off command, which isn't what a toggle means.
    private func pressPowerKey() async throws {
        try await keys.press(.powerOff, on: nil)
    }

    /// Wake-on-LAN, and SmartThings in the background when available; succeeds if either can.
    private func wakeFromDeepStandby(cloudTV: TV?) async throws {
        if let cloudTV {
            let cloud = cloud
            Task { try? await cloud.send(RemoteKey.powerOn.command, to: cloudTV) }
        }
        do {
            try await wake()
        } catch {
            guard cloudTV != nil else { throw error }
        }
    }
}
