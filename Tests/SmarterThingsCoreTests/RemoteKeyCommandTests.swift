import Testing
@testable import SmarterThingsCore

struct RemoteKeyCommandTests {
    @Test(arguments: [
        (RemoteKey.powerOn, TVCommand(capability: "switch", command: "on")),
        (.powerOff, TVCommand(capability: "switch", command: "off")),
        (.volumeUp, TVCommand(capability: "audioVolume", command: "volumeUp")),
        (.volumeDown, TVCommand(capability: "audioVolume", command: "volumeDown")),
        (.mute, TVCommand(capability: "audioMute", command: "mute")),
        (.unmute, TVCommand(capability: "audioMute", command: "unmute")),
        (.channelUp, TVCommand(capability: "tvChannel", command: "channelUp")),
        (.channelDown, TVCommand(capability: "tvChannel", command: "channelDown")),
        (.play, TVCommand(capability: "mediaPlayback", command: "play")),
        (.pause, TVCommand(capability: "mediaPlayback", command: "pause")),
        (.stop, TVCommand(capability: "mediaPlayback", command: "stop")),
        (.rewind, TVCommand(capability: "mediaPlayback", command: "rewind")),
        (.fastForward, TVCommand(capability: "mediaPlayback", command: "fastForward")),
    ])
    func keyMapsToCapabilityCommand(key: RemoteKey, expected: TVCommand) {
        #expect(key.command == expected)
    }

    @Test(arguments: [
        (RemoteKey.up, "UP"), (.down, "DOWN"), (.left, "LEFT"), (.right, "RIGHT"),
        (.ok, "OK"), (.back, "BACK"), (.home, "HOME"), (.menu, "MENU"), (.source, "SOURCE"),
    ])
    func navigationKeySendsPressAndRelease(key: RemoteKey, keyValue: String) {
        #expect(key.command == TVCommand(
            capability: "samsungvd.remoteControl",
            command: "send",
            arguments: [keyValue, "PRESS_AND_RELEASED"]
        ))
    }
}
