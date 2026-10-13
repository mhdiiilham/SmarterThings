/// Finds the TV's LAN address: a manually entered address wins, otherwise SSDP discovery.
public actor TVHostFinder {
    private let manualHost: @Sendable () -> String?
    private let discover: @Sendable () async -> [String]
    private var discoveredHost: String?

    public init(
        manualHost: @escaping @Sendable () -> String?,
        discover: @escaping @Sendable () async -> [String] = { await SSDPDiscovery.samsungTVHosts() }
    ) {
        self.manualHost = manualHost
        self.discover = discover
    }

    public func host() async throws -> String {
        if let manual = manualHost(), !manual.isEmpty { return manual }
        if let discoveredHost { return discoveredHost }
        guard let found = await discover().first else { throw KeyboardError.tvNotFound }
        discoveredHost = found
        return found
    }

    /// Call after a connection failure so the next attempt searches again.
    public func forgetDiscoveredHost() {
        discoveredHost = nil
    }
}
