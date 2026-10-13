import Foundation

/// Sends remote keys the fastest way available. Keys in `localKeys` go over the local
/// network (no rate limit, no token). The cloud is only a fallback, and only when a
/// SmartThings TV is given: if the local connection isn't ready within `localTimeout`
/// that press goes via the cloud while the connection keeps opening; if local fails
/// outright (e.g. away from home) it's skipped for `localRetryInterval`.
/// Without a SmartThings TV, local failures are reported instead.
public actor KeyDispatcher {
    public enum Route: String, Sendable {
        case local
        case cloud
    }

    private struct LocalTimeout: Error {}

    private let local: TVKeyPresser
    private let cloud: TVController
    private let localKeys: Set<RemoteKey>
    private let localTimeout: Duration
    private let localRetryInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var localPausedUntil: Date?

    public init(
        local: TVKeyPresser,
        cloud: TVController,
        localKeys: Set<RemoteKey>,
        localTimeout: Duration = .milliseconds(1500),
        localRetryInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.local = local
        self.cloud = cloud
        self.localKeys = localKeys
        self.localTimeout = localTimeout
        self.localRetryInterval = localRetryInterval
        self.now = now
    }

    /// Opens the local connection ahead of time so the first press is instant.
    public func warmUp() async {
        guard isLocalAvailable else { return }
        do {
            try await local.prepare()
        } catch {
            localPausedUntil = now().addingTimeInterval(localRetryInterval)
        }
    }

    /// `cloudTV` is the matching SmartThings TV, or `nil` when there's no token.
    @discardableResult
    public func press(_ key: RemoteKey, on cloudTV: TV?) async throws -> Route {
        let isLocalKey = localKeys.contains(key)
        if isLocalKey, isLocalAvailable || cloudTV == nil {
            do {
                try await pressLocally(key, waitingForConnection: cloudTV == nil)
                return .local
            } catch is LocalTimeout {
                // Still connecting (or waiting for "Allow"): use the cloud this time only.
            } catch {
                guard cloudTV != nil else { throw error }
                localPausedUntil = now().addingTimeInterval(localRetryInterval)
            }
        }
        guard let cloudTV else { throw isLocalKey ? LocalTVError.noResponse : LocalTVError.unsupportedKey }
        try await cloud.send(key.command, to: cloudTV)
        return .cloud
    }

    /// With no cloud to fall back to, there's no point giving up early: wait for the
    /// connection (and the TV's "Allow") instead of timing out.
    private func pressLocally(_ key: RemoteKey, waitingForConnection: Bool) async throws {
        if waitingForConnection {
            try await local.press(key)
            return
        }
        let local = local
        let timeout = localTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await local.press(key) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocalTimeout()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private var isLocalAvailable: Bool {
        guard let localPausedUntil else { return true }
        return now() >= localPausedUntil
    }
}
