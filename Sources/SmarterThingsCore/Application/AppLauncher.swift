/// Opens apps over the local network, falling back to SmartThings' `custom.launchapp`
/// when a SmartThings TV (token) is available.
public struct AppLauncher: Sendable {
    private let local: TVAppOpener
    private let cloud: TVController

    public init(local: TVAppOpener, cloud: TVController) {
        self.local = local
        self.cloud = cloud
    }

    public func open(_ app: TVApp, cloudTV: TV?) async throws {
        do {
            try await local.open(app)
        } catch {
            guard let cloudTV, cloudTV.canLaunchApps else { throw error }
            try await cloud.send(.launch(app), to: cloudTV)
        }
    }
}
