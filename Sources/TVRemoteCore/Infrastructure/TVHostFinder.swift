/// Finds the TV's LAN address. Discovery comes first so a changed IP (DHCP) is picked up;
/// a manually entered address is only the fallback when discovery finds nothing.
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
        if let discoveredHost { return discoveredHost }
        if let found = await discover().first {
            discoveredHost = found
            return found
        }
        if let manual = manualHost(), !manual.isEmpty { return manual }
        throw LocalTVError.tvNotFound
    }

    /// Call after a connection failure so the next attempt searches again.
    public func forgetDiscoveredHost() {
        discoveredHost = nil
    }
}
