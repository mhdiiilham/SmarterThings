public protocol TokenStore: Sendable {
    func token() -> String?
    func save(_ token: String) throws
    func clear() throws
}
