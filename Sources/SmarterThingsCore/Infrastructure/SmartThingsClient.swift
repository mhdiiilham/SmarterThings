import Foundation

/// Talks to the SmartThings cloud REST API (https://api.smartthings.com/v1).
public struct SmartThingsClient: TVController {
    private let tokenStore: TokenStore
    private let transport: HTTPTransport
    private let baseURL: URL

    public init(
        tokenStore: TokenStore,
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://api.smartthings.com/v1")!
    ) {
        self.tokenStore = tokenStore
        self.transport = transport
        self.baseURL = baseURL
    }

    public func televisions() async throws -> [TV] {
        let data = try await perform(request(path: "devices"))
        let page = try JSONDecoder().decode(DevicePage.self, from: data)
        return page.items.map(\.tv).filter(\.isTelevision)
    }

    public func inputSources(of tv: TV) async throws -> [InputSource] {
        guard let capability = tv.inputSourceCapability else { return [] }
        let data = try await perform(request(path: statusPath(of: tv, capability: capability)))
        return try JSONDecoder().decode(InputSourceStatus.self, from: data).sources
    }

    public func isPoweredOn(_ tv: TV) async throws -> Bool {
        let data = try await perform(request(path: statusPath(of: tv, capability: "switch")))
        return try JSONDecoder().decode(SwitchStatus.self, from: data).switch.value == "on"
    }

    public func send(_ command: TVCommand, to tv: TV) async throws {
        var commandRequest = try request(path: "devices/\(tv.id)/commands")
        commandRequest.httpMethod = "POST"
        commandRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        commandRequest.httpBody = try JSONEncoder().encode(CommandBatch(command))
        _ = try await perform(commandRequest)
    }

    private func statusPath(of tv: TV, capability: String) -> String {
        "devices/\(tv.id)/components/main/capabilities/\(capability)/status"
    }

    private func request(path: String) throws -> URLRequest {
        guard let token = tokenStore.token(), !token.isEmpty else { throw RemoteError.missingToken }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw RemoteError.tokenExpired
        case 429: throw RemoteError.rateLimited(retryAfter: Self.secondsUntilReset(response))
        default: throw RemoteError.requestFailed(status: response.statusCode)
        }
    }

    /// `x-ratelimit-reset` is the time left in the window, in milliseconds.
    private static func secondsUntilReset(_ response: HTTPURLResponse) -> Int? {
        guard let header = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
              let milliseconds = Double(header) else { return nil }
        return max(1, Int((milliseconds / 1000).rounded(.up)))
    }
}

// MARK: - Wire format

private struct DevicePage: Decodable {
    let items: [Device]
}

private struct Device: Decodable {
    let deviceId: String
    let label: String?
    let name: String?
    let components: [Component]

    struct Component: Decodable {
        let id: String
        let capabilities: [Capability]
    }

    struct Capability: Decodable {
        let id: String
    }

    var tv: TV {
        let main = components.first { $0.id == "main" }
        return TV(
            id: deviceId,
            name: label ?? name ?? deviceId,
            capabilities: Set(main?.capabilities.map(\.id) ?? [])
        )
    }
}

/// Status of either `samsungvd.mediaInputSource` (id + friendly name map)
/// or the generic `mediaInputSource` (plain id list).
private struct InputSourceStatus: Decodable {
    let supportedInputSourcesMap: Attribute<[NamedSource]>?
    let supportedInputSources: Attribute<[String]>?

    struct Attribute<Value: Decodable>: Decodable {
        let value: Value?
    }

    struct NamedSource: Decodable {
        let id: String
        let name: String
    }

    var sources: [InputSource] {
        if let named = supportedInputSourcesMap?.value {
            return named.map { InputSource(id: $0.id, name: $0.name) }
        }
        return (supportedInputSources?.value ?? []).map { InputSource(id: $0, name: $0) }
    }
}

private struct SwitchStatus: Decodable {
    let `switch`: Value

    struct Value: Decodable {
        let value: String?
    }
}

private struct CommandBatch: Encodable {
    let commands: [Command]

    struct Command: Encodable {
        let component = "main"
        let capability: String
        let command: String
        let arguments: [String]
    }

    init(_ command: TVCommand) {
        commands = [Command(capability: command.capability, command: command.command, arguments: command.arguments)]
    }
}
