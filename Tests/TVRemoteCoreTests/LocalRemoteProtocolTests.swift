import Foundation
import Testing
@testable import TVRemoteCore

struct LocalRemoteProtocolTests {
    @Test func connectURLEncodesAppNameAndToken() {
        let url = LocalRemoteProtocol.connectURL(host: "192.168.1.20", appName: "Mac", token: "1234")
        #expect(url.absoluteString
            == "wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=TWFj&token=1234")
    }

    @Test func connectURLOmitsMissingToken() {
        let url = LocalRemoteProtocol.connectURL(host: "tv.local", appName: "Mac", token: nil)
        #expect(url.query == "name=TWFj")
    }

    @Test func textMessageSendsBase64InputString() throws {
        let params = try params(of: LocalRemoteProtocol.textMessage("lofi"))
        #expect(params == ["Cmd": "bG9maQ==", "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"])
    }

    @Test func inputEndMessageEndsInput() throws {
        #expect(try params(of: LocalRemoteProtocol.inputEndMessage) == ["TypeOfRemote": "SendInputEnd"])
    }

    @Test(arguments: [
        (#"{"event":"ms.channel.connect","data":{"token":"5678"}}"#, LocalRemoteProtocol.Event.connected(token: "5678")),
        (#"{"event":"ms.channel.connect","data":{}}"#, .connected(token: nil)),
        (#"{"event":"ms.channel.unauthorized"}"#, .unauthorized),
        (#"{"event":"ed.installedApp.get"}"#, .other),
        ("not json", .other),
    ])
    func parsesEvents(message: String, expected: LocalRemoteProtocol.Event) {
        #expect(LocalRemoteProtocol.parseEvent(message) == expected)
    }

    @Test func installedAppsRequestEmitsToHost() throws {
        let json = try object(LocalRemoteProtocol.installedAppsRequest)
        #expect(json["method"] as? String == "ms.channel.emit")
        #expect(json["params"] as? [String: String] == ["event": "ed.installedApp.get", "to": "host"])
    }

    @Test(arguments: [(TVApp.Kind.deepLink, "DEEP_LINK"), (.native, "NATIVE_LAUNCH")])
    func launchMessageUsesActionTypeForKind(kind: TVApp.Kind, actionType: String) throws {
        let app = TVApp(id: "111299001912", name: "YouTube", kind: kind)
        let params = try #require(try object(LocalRemoteProtocol.launchMessage(app))["params"] as? [String: Any])
        #expect(params["event"] as? String == "ed.apps.launch")
        #expect(params["data"] as? [String: String] == ["appId": "111299001912", "action_type": actionType])
    }

    @Test func parsesInstalledApps() {
        let message = #"""
        {"event":"ed.installedApp.get","data":{"data":[
          {"appId":"111299001912","name":"YouTube","app_type":2},
          {"appId":"3201907018807","name":"Netflix","app_type":4},
          {"name":"broken entry"}]}}
        """#
        #expect(LocalRemoteProtocol.parseInstalledApps(message) == [
            TVApp(id: "111299001912", name: "YouTube", kind: .deepLink),
            TVApp(id: "3201907018807", name: "Netflix", kind: .native),
        ])
    }

    @Test func otherEventsAreNotAppLists() {
        #expect(LocalRemoteProtocol.parseInstalledApps(#"{"event":"ms.channel.clientConnect"}"#) == nil)
    }

    private func object(_ message: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
    }

    private func params(of message: String) throws -> [String: String]? {
        let json = try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any]
        #expect(json?["method"] as? String == "ms.remote.control")
        return json?["params"] as? [String: String]
    }
}
