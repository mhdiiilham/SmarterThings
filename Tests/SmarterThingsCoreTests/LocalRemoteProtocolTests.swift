import Foundation
import Testing
@testable import SmarterThingsCore

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

    @Test(arguments: [
        (RemoteKey.up, "KEY_UP"), (.down, "KEY_DOWN"), (.left, "KEY_LEFT"), (.right, "KEY_RIGHT"),
        (.ok, "KEY_ENTER"), (.volumeUp, "KEY_VOLUP"), (.volumeDown, "KEY_VOLDOWN"),
    ])
    func keyMessageClicksSamsungKeyCode(key: RemoteKey, code: String) throws {
        let message = try #require(LocalRemoteProtocol.keyMessage(key))
        #expect(try params(of: message)
            == ["Cmd": "Click", "DataOfCmd": code, "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }

    @Test(arguments: RemoteKey.allCases.filter { $0 != .powerOn })
    func everyKeyButPowerOnHasALocalCode(key: RemoteKey) {
        #expect(LocalRemoteProtocol.keyMessage(key) != nil)
    }

    @Test(arguments: [
        (RemoteKey.back, "KEY_RETURN"), (.home, "KEY_HOME"), (.menu, "KEY_MENU"), (.source, "KEY_SOURCE"),
        (.mute, "KEY_MUTE"), (.unmute, "KEY_MUTE"), (.powerOff, "KEY_POWER"), (.fastForward, "KEY_FF"),
    ])
    func usesSamsungKeyCodes(key: RemoteKey, code: String) throws {
        let message = try #require(LocalRemoteProtocol.keyMessage(key))
        #expect(try params(of: message)?["DataOfCmd"] == code)
    }

    @Test func powerOnHasNoLocalCodeBecauseStandbyTVsUseWakeOnLAN() {
        #expect(LocalRemoteProtocol.keyMessage(.powerOn) == nil)
    }

    private func params(of message: String) throws -> [String: String]? {
        let json = try JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any]
        #expect(json?["method"] as? String == "ms.remote.control")
        return json?["params"] as? [String: String]
    }
}
