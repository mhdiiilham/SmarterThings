public enum RemoteKey: CaseIterable, Sendable {
    case powerOn, powerOff
    case volumeUp, volumeDown, mute, unmute
    case channelUp, channelDown
    case up, down, left, right, ok, back, home, menu
    case play, pause, stop, rewind, fastForward

    public var command: TVCommand {
        switch self {
        case .powerOn: TVCommand(capability: "switch", command: "on")
        case .powerOff: TVCommand(capability: "switch", command: "off")
        case .volumeUp: TVCommand(capability: "audioVolume", command: "volumeUp")
        case .volumeDown: TVCommand(capability: "audioVolume", command: "volumeDown")
        case .mute: TVCommand(capability: "audioMute", command: "mute")
        case .unmute: TVCommand(capability: "audioMute", command: "unmute")
        case .channelUp: TVCommand(capability: "tvChannel", command: "channelUp")
        case .channelDown: TVCommand(capability: "tvChannel", command: "channelDown")
        case .up: Self.navigation("UP")
        case .down: Self.navigation("DOWN")
        case .left: Self.navigation("LEFT")
        case .right: Self.navigation("RIGHT")
        case .ok: Self.navigation("OK")
        case .back: Self.navigation("BACK")
        case .home: Self.navigation("HOME")
        case .menu: Self.navigation("MENU")
        case .play: TVCommand(capability: "mediaPlayback", command: "play")
        case .pause: TVCommand(capability: "mediaPlayback", command: "pause")
        case .stop: TVCommand(capability: "mediaPlayback", command: "stop")
        case .rewind: TVCommand(capability: "mediaPlayback", command: "rewind")
        case .fastForward: TVCommand(capability: "mediaPlayback", command: "fastForward")
        }
    }

    private static func navigation(_ keyValue: String) -> TVCommand {
        TVCommand(
            capability: "samsungvd.remoteControl",
            command: "send",
            arguments: [keyValue, "PRESS_AND_RELEASED"]
        )
    }
}
