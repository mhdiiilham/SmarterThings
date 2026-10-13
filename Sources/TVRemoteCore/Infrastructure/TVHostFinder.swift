/// Finds the TV's LAN address. Discovery runs on every new connection so a changed IP
/// (DHCP) is picked up; the chosen TV is matched by its UUID, never by IP.
/// A manually entered address is only the fallback when discovery finds nothing.
public actor TVHostFinder {
    private let manualHost: @Sendable () -> String?
    private let chosenDeviceID: @Sendable () -> String?
    private let discover: @Sendable () async -> [LocalTVDevice]
    private var discoveredHost: String?

    public init(
        manualHost: @escaping @Sendable () -> String?,
        chosenDeviceID: @escaping @Sendable () -> String? = { nil },
        discover: @escaping @Sendable () async -> [LocalTVDevice] = { await LocalTVDiscovery.devices() }
    ) {
        self.manualHost = manualHost
        self.chosenDeviceID = chosenDeviceID
        self.discover = discover
    }

    public func devices() async -> [LocalTVDevice] {
        await discover()
    }

    public func host() async throws -> String {
        if let discoveredHost { return discoveredHost }
        let devices = await discover()
        let chosenID = chosenDeviceID()
        if let device = devices.first(where: { $0.id == chosenID }) ?? devices.first {
            discoveredHost = device.host
            return device.host
        }
        if let manual = manualHost(), !manual.isEmpty { return manual }
        throw LocalTVError.tvNotFound
    }

    /// Call after a connection failure or a TV switch so the next attempt searches again.
    public func forgetDiscoveredHost() {
        discoveredHost = nil
    }
}
