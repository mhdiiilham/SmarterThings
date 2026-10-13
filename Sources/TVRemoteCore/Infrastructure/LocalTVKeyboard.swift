import Foundation

/// Types text on the TV over its local remote WebSocket (wss, port 8002).
/// The first connection makes the TV ask "Allow?"; the token it then sends is reused.
public actor LocalTVKeyboard: TVKeyboard {
    private let hostFinder: TVHostFinder
    private let tokenStore: TokenStore
    private let appName: String
    private let approvalTimeout: Duration
    private var socket: URLSessionWebSocketTask?

    public init(
        hostFinder: TVHostFinder,
        tokenStore: TokenStore,
        appName: String = "TV Remote (Mac)",
        approvalTimeout: Duration = .seconds(30)
    ) {
        self.hostFinder = hostFinder
        self.tokenStore = tokenStore
        self.appName = appName
        self.approvalTimeout = approvalTimeout
    }

    public func type(_ text: String) async throws {
        do {
            try await send(text, over: connectedSocket())
        } catch let error as KeyboardError {
            throw error
        } catch {
            // The TV drops idle connections; reconnect once before giving up.
            socket = nil
            try await send(text, over: connectedSocket())
        }
    }

    private func send(_ text: String, over socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.string(LocalRemoteProtocol.textMessage(text)))
        try await socket.send(.string(LocalRemoteProtocol.inputEndMessage))
    }

    private func connectedSocket() async throws -> URLSessionWebSocketTask {
        if let socket, socket.closeCode == .invalid, socket.state == .running { return socket }

        let host = try await hostFinder.host()
        let url = LocalRemoteProtocol.connectURL(host: host, appName: appName, token: tokenStore.token())
        let session = URLSession(configuration: .ephemeral, delegate: SelfSignedTVTrust(host: host), delegateQueue: nil)
        let newSocket = session.webSocketTask(with: url)
        newSocket.resume()

        do {
            switch try await firstEvent(on: newSocket) {
            case .connected(let token):
                if let token { try? tokenStore.save(token) }
                socket = newSocket
                return newSocket
            case .unauthorized:
                newSocket.cancel()
                throw KeyboardError.accessDenied
            case .other:
                newSocket.cancel()
                throw KeyboardError.noResponse
            }
        } catch let error as KeyboardError {
            throw error
        } catch {
            newSocket.cancel()
            await hostFinder.forgetDiscoveredHost()
            throw KeyboardError.tvNotFound
        }
    }

    /// Waits for the connect/unauthorized event, giving the user time to click Allow on the TV.
    private func firstEvent(on socket: URLSessionWebSocketTask) async throws -> LocalRemoteProtocol.Event {
        let timeout = approvalTimeout
        return try await withThrowingTaskGroup(of: LocalRemoteProtocol.Event.self) { group in
            group.addTask {
                while true {
                    guard case .string(let message) = try await socket.receive() else { continue }
                    let event = LocalRemoteProtocol.parseEvent(message)
                    if event != .other { return event }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                // receive() ignores task cancellation; closing the socket is what unblocks it.
                socket.cancel(with: .goingAway, reason: nil)
                throw KeyboardError.noResponse
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
