/// Port for typing text into whatever on-screen keyboard is open on the TV.
public protocol TVKeyboard: Sendable {
    func type(_ text: String) async throws
}

/// Failures of the direct (local network) connection to the TV.
public enum LocalTVError: Error, Equatable {
    case tvNotFound
    case accessDenied
    case noResponse
}
