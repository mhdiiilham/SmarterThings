import Foundation
import Testing
@testable import TVRemoteCore

struct SmartThingsClientTests {
    private let tv = TV(id: "tv-1", name: "Living Room", capabilities: ["samsungvd.mediaInputSource"])

    @Test func sendPostsCommandWithBearerToken() async throws {
        let transport = FakeTransport(responses: [(204, "")])
        try await makeClient(transport).send(RemoteKey.volumeUp.command, to: tv)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.smartthings.com/v1/devices/tv-1/commands")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        let command = try #require((body?["commands"] as? [[String: Any]])?.first)
        #expect(command["component"] as? String == "main")
        #expect(command["capability"] as? String == "audioVolume")
        #expect(command["command"] as? String == "volumeUp")
        #expect(command["arguments"] as? [String] == [])
    }

    @Test func televisionsKeepsOnlyTVsAndPrefersLabel() async throws {
        let transport = FakeTransport(responses: [(200, Fixture.devices)])
        let tvs = try await makeClient(transport).televisions()

        #expect(tvs.map(\.name) == ["Living Room TV"])
        #expect(tvs.first?.capabilities.contains("samsungvd.remoteControl") == true)
        #expect(transport.requests.first?.url?.path == "/v1/devices")
    }

    @Test func inputSourcesUseFriendlyNamesWhenAvailable() async throws {
        let transport = FakeTransport(responses: [(200, Fixture.samsungInputStatus)])
        let sources = try await makeClient(transport).inputSources(of: tv)

        #expect(sources == [InputSource(id: "dtv", name: "TV"), InputSource(id: "HDMI1", name: "PlayStation")])
        #expect(transport.requests.first?.url?.path
            == "/v1/devices/tv-1/components/main/capabilities/samsungvd.mediaInputSource/status")
    }

    @Test func inputSourcesFallBackToPlainIDs() async throws {
        let transport = FakeTransport(responses: [(200, Fixture.genericInputStatus)])
        let plainTV = TV(id: "tv-1", name: "TV", capabilities: ["mediaInputSource"])
        let sources = try await makeClient(transport).inputSources(of: plainTV)

        #expect(sources.map(\.id) == ["digitalTv", "HDMI1"])
    }

    @Test(arguments: [("on", true), ("off", false)])
    func powerStateComesFromSwitchStatus(value: String, expected: Bool) async throws {
        let transport = FakeTransport(responses: [(200, #"{"switch": {"value": "\#(value)"}}"#)])
        let isOn = try await makeClient(transport).isPoweredOn(tv)

        #expect(isOn == expected)
        #expect(transport.requests.first?.url?.path == "/v1/devices/tv-1/components/main/capabilities/switch/status")
    }

    @Test func unauthorizedMeansTokenExpired() async {
        let client = makeClient(FakeTransport(responses: [(401, "")]))
        await #expect(throws: RemoteError.tokenExpired) { try await client.televisions() }
    }

    @Test func otherFailuresReportStatus() async {
        let client = makeClient(FakeTransport(responses: [(500, "")]))
        await #expect(throws: RemoteError.requestFailed(status: 500)) { try await client.send(RemoteKey.ok.command, to: tv) }
    }

    @Test func missingTokenFailsWithoutCallingAPI() async {
        let transport = FakeTransport(responses: [])
        let client = SmartThingsClient(tokenStore: InMemoryTokenStore(), transport: transport)
        await #expect(throws: RemoteError.missingToken) { try await client.televisions() }
        #expect(transport.requests.isEmpty)
    }

    private func makeClient(_ transport: FakeTransport) -> SmartThingsClient {
        SmartThingsClient(tokenStore: InMemoryTokenStore(storedToken: "secret"), transport: transport)
    }
}

// MARK: - Fakes

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var storedToken: String?

    init(storedToken: String? = nil) {
        self.storedToken = storedToken
    }

    func token() -> String? { storedToken }
    func save(_ token: String) { storedToken = token }
    func clear() { storedToken = nil }
}

// MARK: - Fixtures (shape of SmartThings API responses)

private enum Fixture {
    static let devices = """
    {"items": [
      {"deviceId": "tv-1", "name": "[TV] Samsung Q80 Series", "label": "Living Room TV",
       "components": [{"id": "main", "capabilities": [
         {"id": "switch"}, {"id": "audioVolume"}, {"id": "samsungvd.remoteControl"}]}]},
      {"deviceId": "plug-1", "name": "Smart Plug", "label": null,
       "components": [{"id": "main", "capabilities": [{"id": "switch"}]}]}
    ], "_links": {}}
    """

    static let samsungInputStatus = """
    {"inputSource": {"value": "HDMI1"},
     "supportedInputSourcesMap": {"value": [{"id": "dtv", "name": "TV"}, {"id": "HDMI1", "name": "PlayStation"}]}}
    """

    static let genericInputStatus = """
    {"inputSource": {"value": "HDMI1"}, "supportedInputSources": {"value": ["digitalTv", "HDMI1"]}}
    """
}
