import Testing
@testable import TVRemoteCore

struct TVTests {
    @Test func deviceWithRemoteControlIsTelevision() {
        #expect(makeTV(["switch", "samsungvd.remoteControl"]).isTelevision)
    }

    @Test func plainSwitchIsNotTelevision() {
        #expect(!makeTV(["switch"]).isTelevision)
    }

    @Test func supportsOnlyKeysWhoseCapabilityItHas() {
        let tv = makeTV(["audioVolume"])
        #expect(tv.supports(.volumeUp))
        #expect(!tv.supports(.play))
    }

    @Test func prefersSamsungInputSourceCapability() {
        let tv = makeTV(["mediaInputSource", "samsungvd.mediaInputSource"])
        #expect(tv.inputSourceCapability == "samsungvd.mediaInputSource")
    }

    @Test func selectInputUsesTheTVsInputCapability() {
        let tv = makeTV(["mediaInputSource"])
        let hdmi = InputSource(id: "HDMI1", name: "HDMI1")
        #expect(tv.selectInputCommand(hdmi) == TVCommand(
            capability: "mediaInputSource", command: "setInputSource", arguments: ["HDMI1"]
        ))
    }

    @Test func cannotSelectInputWithoutInputCapability() {
        #expect(makeTV(["switch"]).selectInputCommand(InputSource(id: "HDMI1", name: "HDMI1")) == nil)
    }

    private func makeTV(_ capabilities: Set<String>) -> TV {
        TV(id: "tv-1", name: "Living Room", capabilities: capabilities)
    }
}
