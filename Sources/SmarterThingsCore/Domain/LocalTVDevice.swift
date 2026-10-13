/// A Samsung TV found on the local network.
/// `id` is the TV's own UUID, which stays the same when its IP address changes.
public struct LocalTVDevice: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    /// Wi-Fi MAC address, needed to wake the TV from standby (Wake-on-LAN).
    public let macAddress: String?

    public init(id: String, name: String, host: String, macAddress: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.macAddress = macAddress
    }
}
