/// Port for typing text into whatever on-screen keyboard is open on the TV.
public protocol TVKeyboard: Sendable {
    func type(_ text: String) async throws
}

public enum KeyboardError: Error, Equatable {
    case tvNotFound
    case accessDenied
    case noResponse
}
