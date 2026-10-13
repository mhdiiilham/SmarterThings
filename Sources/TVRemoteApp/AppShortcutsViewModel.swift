import Foundation
import Observation
import TVRemoteCore

@MainActor
@Observable
final class AppShortcutsViewModel {
    enum Status: Equatable {
        case idle
        case loading
        case failed(String)
    }

    static let maxFavorites = 4
    private static let favoritesKey = "favoriteApps"

    private(set) var favorites: [TVApp]
    private(set) var installedApps: [TVApp] = []
    private(set) var status: Status = .idle
    private(set) var isEditing = false

    private let launcher: TVAppLauncher
    private let defaults: UserDefaults

    init(launcher: TVAppLauncher, defaults: UserDefaults = .standard) {
        self.launcher = launcher
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.favoritesKey)
        favorites = saved.flatMap { try? JSONDecoder().decode([TVApp].self, from: $0) } ?? []
    }

    var canAddFavorite: Bool { favorites.count < Self.maxFavorites }

    func launch(_ app: TVApp) {
        Task {
            do {
                try await launcher.launch(app)
                status = .idle
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    func startEditing() async {
        isEditing = true
        status = .loading
        do {
            installedApps = try await launcher.installedApps().sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            status = installedApps.isEmpty ? .failed("The TV didn't return any apps.") : .idle
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    func finishEditing() {
        isEditing = false
        status = .idle
    }

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

    private static func message(for error: Error) -> String {
        switch error {
        case LocalTVError.tvNotFound: "Couldn't reach the TV on this network."
        case LocalTVError.accessDenied: "The TV blocked this Mac. Allow \"TV Remote (Mac)\" on the TV."
        case LocalTVError.noResponse: "The TV didn't answer. Try again."
        default: error.localizedDescription
        }
    }
}
