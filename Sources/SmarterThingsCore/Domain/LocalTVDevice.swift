/// A Samsung TV found on the local network.
/// `id` is the TV's own UUID, which stays the same when its IP address changes.
public struct LocalTVDevice: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let host: String

    public init(id: String, name: String, host: String) {
        self.id = id
        self.name = name
        self.host = host
    }
}
