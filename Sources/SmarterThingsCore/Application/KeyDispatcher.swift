import Foundation

/// Sends remote keys the fastest way available. Keys in `localKeys` go over the local
/// network (no rate limit); if that fails, e.g. away from home, they fall back to the
/// cloud and local is skipped for `localRetryInterval` so presses don't keep waiting
/// on a connection that won't come. Every other key always uses the cloud.
public actor KeyDispatcher {
    private let local: TVKeyPresser
    private let cloud: TVController
    private let localKeys: Set<RemoteKey>
    private let localRetryInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var localPausedUntil: Date?

    public init(
        local: TVKeyPresser,
        cloud: TVController,
        localKeys: Set<RemoteKey>,
        localRetryInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.local = local
        self.cloud = cloud
        self.localKeys = localKeys
        self.localRetryInterval = localRetryInterval
        self.now = now
    }

    public func press(_ key: RemoteKey, on tv: TV) async throws {
        if localKeys.contains(key), isLocalAvailable {
            do {
                try await local.press(key)
                return
            } catch {
                localPausedUntil = now().addingTimeInterval(localRetryInterval)
            }
        }
        try await cloud.send(key.command, to: tv)
    }

    private var isLocalAvailable: Bool {
        guard let localPausedUntil else { return true }
        return now() >= localPausedUntil
    }
}
