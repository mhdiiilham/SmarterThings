import Foundation
import OSLog

private let connectionLog = Logger(subsystem: "com.mhdiiilham.SmarterThings", category: "connection")

/// Talks to the TV directly over its local remote WebSocket (wss, port 8002): typing into
/// Samsung's on-screen keyboard (which the cloud can't do) and pressing keys without the
/// cloud's rate limit. The first connection makes the TV ask "Allow?"; its token is reused.
public actor LocalTVRemote: TVKeyboard, TVKeyPresser {
    private let hostFinder: TVHostFinder
    private let tokenStore: TokenStore
    private let appName: String
    private let approvalTimeout: Duration
    private var socket: URLSessionWebSocketTask?
    /// Shared by concurrent callers so rapid presses open one connection (and one prompt).
    private var pendingConnection: Task<URLSessionWebSocketTask, Error>?
    private var keepAlive: Task<Void, Never>?
    /// The TV closes idle connections; a ping this often keeps the next press instant.
    private let keepAliveInterval: Duration = .seconds(10)
    /// No pong in this time means the connection is dead even if it still looks open.
    private let pongDeadline: Duration = .seconds(3)
    /// A send that takes longer means the connection has stalled (the TV stopped reading,
    /// Wi-Fi power saving, the Mac woke from sleep). Waiting made presses pile up and then
    /// all arrive at once; replacing the connection is faster.
    private let sendDeadline: Duration = .seconds(1)

    private struct StalledConnection: Error {}

    public init(
        hostFinder: TVHostFinder,
        tokenStore: TokenStore,
        appName: String = "SmarterThings (Mac)",
        approvalTimeout: Duration = .seconds(30)
    ) {
        self.hostFinder = hostFinder
        self.tokenStore = tokenStore
        self.appName = appName
        self.approvalTimeout = approvalTimeout
    }

    public func type(_ text: String) async throws {
        try await withSocket { socket in
            try await socket.send(.string(LocalRemoteProtocol.textMessage(text)))
            try await socket.send(.string(LocalRemoteProtocol.inputEndMessage))
        }
    }


    public func prepare() async throws {
        _ = try await connectedSocket()
    }

    public func press(_ key: RemoteKey) async throws {
        guard let message = LocalRemoteProtocol.keyMessage(key) else { throw LocalTVError.unsupportedKey }
        try await withSocket { socket in
            try await socket.send(.string(message))
        }
    }

    /// Closes the connection, e.g. after switching to another TV.
    public func disconnect() {
        keepAlive?.cancel()
        keepAlive = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Runs `operation` on the open connection. A failed or stalled send gets one retry on a
    /// fresh connection; the stalled one is closed, which also discards presses queued on it
    /// so they can't arrive late as a burst.
    private func withSocket<Result: Sendable>(
        _ operation: @escaping @Sendable (URLSessionWebSocketTask) async throws -> Result
    ) async throws -> Result {
        let current = try await connectedSocket()
        do {
            return try await Self.withDeadline(sendDeadline, closing: current) { try await operation(current) }
        } catch let error as LocalTVError {
            throw error
        } catch {
            connectionLog.notice("send \(error is StalledConnection ? "stalled" : "failed", privacy: .public); reconnecting")
            dropSocket(current)
            let fresh = try await connectedSocket()
            return try await Self.withDeadline(sendDeadline, closing: fresh) { try await operation(fresh) }
        }
    }

    /// Runs `operation`, closing `socket` if it takes longer than `deadline`: a stuck WebSocket
    /// send ignores task cancellation, and closing the socket is what ends it.
    private static func withDeadline<Value: Sendable>(
        _ deadline: Duration,
        closing socket: URLSessionWebSocketTask,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: deadline)
                socket.cancel(with: .goingAway, reason: nil)
                throw StalledConnection()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func connectedSocket() async throws -> URLSessionWebSocketTask {
        if let socket, socket.closeCode == .invalid, socket.state == .running { return socket }
        if let pendingConnection { return try await pendingConnection.value }

        let start = ContinuousClock.now
        let connection = Task { try await openSocket() }
        pendingConnection = connection
        defer { pendingConnection = nil }
        let newSocket = try await connection.value
        connectionLog.notice("connected to TV in \(Self.milliseconds(start.duration(to: .now)), privacy: .public) ms")
        socket = newSocket
        startKeepAlive(for: newSocket)
        return newSocket
    }

    private func startKeepAlive(for socket: URLSessionWebSocketTask) {
        keepAlive?.cancel()
        let interval = keepAliveInterval
        let pongDeadline = pongDeadline
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let start = ContinuousClock.now
                guard await Self.ping(socket, deadline: pongDeadline) else {
                    connectionLog.notice("no pong within \(pongDeadline, privacy: .public); reconnecting")
                    await self?.replaceDeadSocket(socket)
                    return
                }
                let roundTrip = start.duration(to: .now)
                if roundTrip > .milliseconds(500) {
                    connectionLog.notice("slow pong: \(Self.milliseconds(roundTrip), privacy: .public) ms")
                }
            }
        }
    }

    /// `true` if the TV answers the ping in time. On timeout the socket is closed, which
    /// also makes the pending ping finish.
    private static func ping(_ socket: URLSessionWebSocketTask, deadline: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    socket.sendPing { error in continuation.resume(returning: error == nil) }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: deadline)
                } catch {
                    return true   // cancelled because the pong arrived
                }
                socket.cancel(with: .goingAway, reason: nil)
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
    }

    /// Drops a dead connection and opens a new one in the background, so the next press
    /// doesn't pay for reconnecting.
    private func replaceDeadSocket(_ dead: URLSessionWebSocketTask) {
        dropSocket(dead)
        Task { try? await prepare() }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Forgets a dead connection so the next press reconnects right away.
    private func dropSocket(_ dead: URLSessionWebSocketTask) {
        guard socket === dead else { return }
        socket = nil
        keepAlive = nil
    }

    private func openSocket() async throws -> URLSessionWebSocketTask {
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
