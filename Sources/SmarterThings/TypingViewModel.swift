import Foundation
import Observation
import SmarterThingsCore

@MainActor
@Observable
final class TypingViewModel {
    enum Status: Equatable {
        case idle
        case sending
        case sent
        case searched
        case failed(String, canEnterAddress: Bool)
    }

    nonisolated static let manualHostKey = "localTVHost"

    private(set) var status: Status = .idle
    private(set) var manualHost: String

    private let keyboard: TVKeyboard
    private let searchOnTV: (String) async throws -> Void
    private let defaults: UserDefaults

    /// `searchOnTV` runs the TV's own search through SmartThings (works anywhere, no pairing).
    init(
        keyboard: TVKeyboard,
        searchOnTV: @escaping (String) async throws -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.keyboard = keyboard
        self.searchOnTV = searchOnTV
        self.defaults = defaults
        manualHost = defaults.string(forKey: Self.manualHostKey) ?? ""
    }

    func type(_ text: String) async {
        guard !text.isEmpty else { return }
        status = .sending
        do {
            try await keyboard.type(text)
            status = .sent
        } catch {
            status = Self.failure(for: error)
        }
    }

    func search(_ query: String) async {
        guard !query.isEmpty else { return }
        status = .sending
        do {
            try await searchOnTV(query)
            status = .searched
        } catch RemoteError.tokenExpired {
            status = .failed("Your SmartThings token expired. Paste a new one with the key button.", canEnterAddress: false)
        } catch {
            status = .failed("Search failed: \(error.localizedDescription)", canEnterAddress: false)
        }
    }

    func saveManualHost(_ host: String) {
        manualHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(manualHost, forKey: Self.manualHostKey)
        status = .idle
    }

    private static func failure(for error: Error) -> Status {
        switch error {
        case LocalTVError.tvNotFound:
            .failed(
                "Couldn't reach the TV on this network. Check Local Network access for SmarterThings "
                    + "in System Settings › Privacy & Security, or enter the TV's IP address.",
                canEnterAddress: true
            )
        case LocalTVError.accessDenied:
            .failed(
                "The TV blocked this Mac. On the TV, open Settings › General › External Device Manager "
                    + "› Device Connection Manager and allow \"SmarterThings (Mac)\".",
                canEnterAddress: false
            )
        case LocalTVError.noResponse:
            .failed("The TV didn't answer. If it asked to allow this Mac, choose Allow and try again.",
                    canEnterAddress: true)
        default:
            .failed(error.localizedDescription, canEnterAddress: true)
        }
    }
}
