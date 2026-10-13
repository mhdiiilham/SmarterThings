/// Power over the local network. The TV reports its own state:
/// - on: `KEY_POWER` turns it off
/// - standby: it's still listening, so `KEY_POWER` turns it on
/// - unreachable: Wake-on-LAN (needs "Power On with Mobile" on the TV)
/// `KEY_POWER` is a toggle, so every decision is made from a fresh reading.
public struct PowerControl: Sendable {
    private let keys: TVKeyPresser
    private let localPowerState: @Sendable () async -> TVPowerState
    private let wake: @Sendable () async throws -> Void

    /// `wake` sends Wake-on-LAN, throwing if the TV's MAC address isn't known yet.
    public init(
        keys: TVKeyPresser,
        localPowerState: @escaping @Sendable () async -> TVPowerState,
        wake: @escaping @Sendable () async throws -> Void
    ) {
        self.keys = keys
        self.localPowerState = localPowerState
        self.wake = wake
    }

    public func isPoweredOn() async -> Bool {
        await localPowerState() == .on
    }

    /// Returns the new power state.
    @discardableResult
    public func toggle() async throws -> Bool {
        switch await localPowerState() {
        case .on:
            try await keys.press(.powerOff)   // KEY_POWER
            return false
        case .standby:
            try await keys.press(.powerOff)   // KEY_POWER toggles: wakes from standby
            return true
        case .unreachable:
            try await wake()
            return true
        }
    }
}
