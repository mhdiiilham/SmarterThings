/// Port for typing text into whatever on-screen keyboard is open on the TV.
public protocol TVKeyboard: Sendable {
    func type(_ text: String) async throws
}

/// Port for pressing remote keys directly on the TV (fast, no cloud rate limit).
public protocol TVKeyPresser: Sendable {
    /// Opens the connection ahead of the first press (and shows the TV's "Allow" prompt then).
    func prepare() async throws
    func press(_ key: RemoteKey) async throws
}

/// Failures of the direct (local network) connection to the TV.
public enum LocalTVError: Error, Equatable {
    case tvNotFound
    case accessDenied
    case noResponse
    case unsupportedKey
}
