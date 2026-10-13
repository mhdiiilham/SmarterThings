/// An app on the TV, e.g. YouTube. `id` is Samsung's Tizen app ID.
public struct TVApp: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
