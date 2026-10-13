/// Power without the cloud: the TV reports its own power state, `KEY_POWER` turns it off,
/// and Wake-on-LAN turns it on. SmartThings, when available, fills in where the local
/// network can't (state of an unreachable TV, a second way to turn it on).
public struct PowerControl: Sendable {
    private let keys: KeyDispatcher
    private let cloud: TVController
    private let localPowerState: @Sendable () async -> Bool?
    private let wake: @Sendable () async throws -> Void

    /// `localPowerState`: `nil` when the TV doesn't answer. `wake`: sends Wake-on-LAN,
    /// throwing if the TV's MAC address isn't known yet.
    public init(
        keys: KeyDispatcher,
        cloud: TVController,
        localPowerState: @escaping @Sendable () async -> Bool?,
        wake: @escaping @Sendable () async throws -> Void
    ) {
        self.keys = keys
        self.cloud = cloud
        self.localPowerState = localPowerState
        self.wake = wake
    }

    /// `nil` when unknown. A TV that doesn't answer locally and has no cloud is treated as off.
    public func isPoweredOn(cloudTV: TV?) async -> Bool? {
        if let isOn = await localPowerState() { return isOn }
        guard let cloudTV else { return false }
        return try? await cloud.isPoweredOn(cloudTV)
    }

    public func turnOff(cloudTV: TV?) async throws {
        try await keys.press(.powerOff, on: cloudTV)
    }

    /// Wakes the TV locally and, when possible, also asks SmartThings; succeeds if either does.
    public func turnOn(cloudTV: TV?) async throws {
        var wakeError: Error?
        do {
            try await wake()
        } catch {
            wakeError = error
        }
        guard let cloudTV else {
            if let wakeError { throw wakeError }
            return
        }
        do {
            try await cloud.send(RemoteKey.powerOn.command, to: cloudTV)
        } catch {
            if wakeError != nil { throw error }
        }
    }
}
