/// Port for narrowing a list of known apps down to the ones installed on the TV.
public protocol InstalledAppFinder: Sendable {
    func installedApps(among candidates: [TVApp]) async throws -> [TVApp]
}

/// Port for opening an app on the TV.
public protocol TVAppOpener: Sendable {
    func open(_ app: TVApp) async throws
}
