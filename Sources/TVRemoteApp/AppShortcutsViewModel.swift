import Foundation
import Observation
import TVRemoteCore

/// Which apps are pinned as shortcuts. Opening them goes through RemoteViewModel (SmartThings);
/// the picker narrows the known apps to the ones installed on the TV when it can reach it.
@MainActor
@Observable
final class AppShortcutsViewModel {
    static let maxFavorites = 4
    private static let favoritesKey = "favoriteApps"

    private(set) var availableApps: [TVApp]
    private(set) var favorites: [TVApp]
    private(set) var isEditing = false
    private(set) var isCheckingTV = false
    /// True when the TV couldn't be reached and every known app is shown instead.
    private(set) var isShowingAllKnownApps = false

    private let knownApps: [TVApp]
    private let installedAppFinder: InstalledAppFinder
    private let defaults: UserDefaults

    init(knownApps: [TVApp], installedAppFinder: InstalledAppFinder, defaults: UserDefaults = .standard) {
        self.knownApps = knownApps
        self.installedAppFinder = installedAppFinder
        self.defaults = defaults
        availableApps = knownApps
        let saved = defaults.data(forKey: Self.favoritesKey)
        favorites = saved.flatMap { try? JSONDecoder().decode([TVApp].self, from: $0) } ?? []
    }

    var canAddFavorite: Bool { favorites.count < Self.maxFavorites }

    func startEditing() async {
        isEditing = true
        isCheckingTV = true
        do {
            let installed = try await installedAppFinder.installedApps(among: knownApps)
            availableApps = installed.isEmpty ? knownApps : installed
            isShowingAllKnownApps = installed.isEmpty
        } catch {
            availableApps = knownApps
            isShowingAllKnownApps = true
        }
        isCheckingTV = false
    }

    func finishEditing() { isEditing = false }

    func isFavorite(_ app: TVApp) -> Bool {
        favorites.contains { $0.id == app.id }
    }

    func toggleFavorite(_ app: TVApp) {
        if isFavorite(app) {
            favorites.removeAll { $0.id == app.id }
        } else if canAddFavorite {
            favorites.append(app)
        }
        defaults.set(try? JSONEncoder().encode(favorites), forKey: Self.favoritesKey)
    }
}
