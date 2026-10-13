/// Port for narrowing a list of known apps down to the ones installed on the TV.
public protocol InstalledAppFinder: Sendable {
    func installedApps(among candidates: [TVApp]) async throws -> [TVApp]
}
