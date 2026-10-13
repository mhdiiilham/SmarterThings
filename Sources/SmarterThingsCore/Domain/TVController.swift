/// Port to whatever service actually reaches the TV.
public protocol TVController: Sendable {
    func televisions() async throws -> [TV]
    func inputSources(of tv: TV) async throws -> [InputSource]
    func isPoweredOn(_ tv: TV) async throws -> Bool
    func send(_ command: TVCommand, to tv: TV) async throws
}

public enum RemoteError: Error, Equatable {
    case missingToken
    case tokenExpired
    /// SmartThings allows 12 commands per minute per device; `retryAfter` is in seconds.
    case rateLimited(retryAfter: Int?)
    case requestFailed(status: Int)
}
