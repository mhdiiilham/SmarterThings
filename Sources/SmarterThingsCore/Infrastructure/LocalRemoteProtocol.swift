import Foundation

/// Message format of the Samsung Tizen (2016+) local remote WebSocket on port 8002,
/// the same channel Samsung's own phone remote uses.
enum LocalRemoteProtocol {
    enum Event: Equatable {
        /// `token` is only sent the first time, after the user clicks Allow on the TV.
        case connected(token: String?)
        case unauthorized
        case other
    }

    static func connectURL(host: String, appName: String, token: String?) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        components.queryItems = [URLQueryItem(name: "name", value: Data(appName.utf8).base64EncodedString())]
        if let token {
            components.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        return components.url!
    }

    static func textMessage(_ text: String) -> String {
        remoteControl([
            "Cmd": Data(text.utf8).base64EncodedString(),
            "DataOfCmd": "base64",
            "TypeOfRemote": "SendInputString",
        ])
    }

    /// Samsung key codes for remote keys. `powerOn` has none: a TV in standby isn't listening
    /// on this connection, so it's woken with Wake-on-LAN instead. `KEY_POWER` and `KEY_MUTE`
    /// are toggles, so callers only send them when the current state is known.
    private static let keyCodes: [RemoteKey: String] = [
        .powerOff: "KEY_POWER",
        .volumeUp: "KEY_VOLUP", .volumeDown: "KEY_VOLDOWN", .mute: "KEY_MUTE", .unmute: "KEY_MUTE",
        .channelUp: "KEY_CHUP", .channelDown: "KEY_CHDOWN",
        .up: "KEY_UP", .down: "KEY_DOWN", .left: "KEY_LEFT", .right: "KEY_RIGHT", .ok: "KEY_ENTER",
        .back: "KEY_RETURN", .home: "KEY_HOME", .menu: "KEY_MENU",
        .play: "KEY_PLAY", .pause: "KEY_PAUSE", .stop: "KEY_STOP", .rewind: "KEY_REWIND", .fastForward: "KEY_FF",
        .source: "KEY_SOURCE",
    ]

    /// `nil` for keys that have no local key code (`powerOn`).
    static func keyMessage(_ key: RemoteKey) -> String? {
        guard let code = keyCodes[key] else { return nil }
        return remoteControl(["Cmd": "Click", "DataOfCmd": code, "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }

    /// Closes the TV keyboard and applies the text, which submits search fields.
    static let inputEndMessage = remoteControl(["TypeOfRemote": "SendInputEnd"])

    static func parseEvent(_ message: String) -> Event {
        guard let json = jsonObject(message) else { return .other }
        switch json["event"] as? String {
        case "ms.channel.connect":
            let data = json["data"] as? [String: Any]
            return .connected(token: data?["token"] as? String)
        case "ms.channel.unauthorized":
            return .unauthorized
        default:
            return .other
        }
    }

    private static func remoteControl(_ params: [String: String]) -> String {
        encode(["method": "ms.remote.control", "params": params])
    }


    private static func encode(_ message: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: message, options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonObject(_ message: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any]
    }
}
