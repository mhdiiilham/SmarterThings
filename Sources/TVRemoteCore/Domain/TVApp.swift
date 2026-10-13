/// An app installed on the TV, e.g. YouTube or Netflix.
public struct TVApp: Codable, Hashable, Identifiable, Sendable {
    /// Samsung launches web-based apps by deep link and native ones directly.
    public enum Kind: String, Codable, Sendable {
        case deepLink
        case native
    }

    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Port for listing and opening apps on the TV.
public protocol TVAppLauncher: Sendable {
    func installedApps() async throws -> [TVApp]
    func launch(_ app: TVApp) async throws
}
