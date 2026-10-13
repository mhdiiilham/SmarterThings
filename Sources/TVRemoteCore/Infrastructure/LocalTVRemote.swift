import Foundation

/// Talks to the TV directly over its local remote WebSocket (wss, port 8002):
/// typing text and listing/opening apps, which the SmartThings cloud can't do.
/// The first connection makes the TV ask "Allow?"; the token it then sends is reused.
public actor LocalTVRemote: TVKeyboard, TVAppLauncher {
    private let hostFinder: TVHostFinder
    private let tokenStore: TokenStore
    private let appName: String
    private let approvalTimeout: Duration
    private let replyTimeout: Duration
    private var socket: URLSessionWebSocketTask?

    public init(
        hostFinder: TVHostFinder,
        tokenStore: TokenStore,
        appName: String = "TV Remote (Mac)",
        approvalTimeout: Duration = .seconds(30),
        replyTimeout: Duration = .seconds(5)
    ) {
        self.hostFinder = hostFinder
        self.tokenStore = tokenStore
        self.appName = appName
        self.approvalTimeout = approvalTimeout
        self.replyTimeout = replyTimeout
    }

    public func type(_ text: String) async throws {
        try await withSocket { socket in
            try await socket.send(.string(LocalRemoteProtocol.textMessage(text)))
            try await socket.send(.string(LocalRemoteProtocol.inputEndMessage))
        }
    }

    public func installedApps() async throws -> [TVApp] {
        let timeout = replyTimeout
        return try await withSocket { socket in
            try await socket.send(.string(LocalRemoteProtocol.installedAppsRequest))
            return try await Self.firstMatch(on: socket, timeout: timeout, LocalRemoteProtocol.parseInstalledApps)
        }
    }

    public func launch(_ app: TVApp) async throws {
        try await withSocket { socket in
            try await socket.send(.string(LocalRemoteProtocol.launchMessage(app)))
        }
    }

    /// Runs `operation` on the open connection. The TV drops idle connections,
    /// so a transport failure gets one retry on a fresh connection.
    private func withSocket<Result: Sendable>(
        _ operation: @Sendable (URLSessionWebSocketTask) async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation(connectedSocket())
        } catch let error as LocalTVError {
            throw error
        } catch {
            socket = nil
            return try await operation(connectedSocket())
        }
    }

    private func connectedSocket() async throws -> URLSessionWebSocketTask {
        if let socket, socket.closeCode == .invalid, socket.state == .running { return socket }

        let host = try await hostFinder.host()
        let url = LocalRemoteProtocol.connectURL(host: host, appName: appName, token: tokenStore.token())
        let session = URLSession(configuration: .ephemeral, delegate: SelfSignedTVTrust(host: host), delegateQueue: nil)
        let newSocket = session.webSocketTask(with: url)
        newSocket.resume()

        do {
            let event = try await Self.firstMatch(on: newSocket, timeout: approvalTimeout) { message in
                let event = LocalRemoteProtocol.parseEvent(message)
                return event == .other ? nil : event
            }
            switch event {
            case .connected(let token):
                if let token { try? tokenStore.save(token) }
                socket = newSocket
                return newSocket
            case .unauthorized, .other:
                newSocket.cancel()
                throw LocalTVError.accessDenied
            }
        } catch let error as LocalTVError {
            throw error
        } catch {
            newSocket.cancel()
            await hostFinder.forgetDiscoveredHost()
            throw LocalTVError.tvNotFound
        }
    }

    /// Reads messages until `parse` recognizes one, or fails with `noResponse` after `timeout`.
    private static func firstMatch<Value: Sendable>(
        on socket: URLSessionWebSocketTask,
        timeout: Duration,
        _ parse: @escaping @Sendable (String) -> Value?
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                while true {
                    guard case .string(let message) = try await socket.receive() else { continue }
                    if let value = parse(message) { return value }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                // receive() ignores task cancellation; closing the socket is what unblocks it.
                socket.cancel(with: .goingAway, reason: nil)
                throw LocalTVError.noResponse
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

/// Samsung TVs serve a self-signed certificate; trust it only for the TV's own address.
private final class SelfSignedTVTrust: NSObject, URLSessionDelegate, Sendable {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
