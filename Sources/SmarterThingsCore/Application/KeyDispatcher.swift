import Foundation

/// Sends remote keys the fastest way available. Keys in `localKeys` go over the local
/// network (no rate limit). If the local connection isn't ready within `localTimeout`
/// the key goes via the cloud instead, while the connection keeps opening in the
/// background. If local fails outright (e.g. away from home) it is skipped for
/// `localRetryInterval`. Every other key always uses the cloud.
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

    @discardableResult
    public func press(_ key: RemoteKey, on tv: TV) async throws -> Route {
        if localKeys.contains(key), isLocalAvailable {
            do {
                try await pressLocally(key)
                return .local
            } catch is LocalTimeout {
                // Still connecting (or waiting for "Allow"): use the cloud this time only.
            } catch {
                localPausedUntil = now().addingTimeInterval(localRetryInterval)
            }
        }
        try await cloud.send(key.command, to: tv)
        return .cloud
    }

    private func pressLocally(_ key: RemoteKey) async throws {
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
