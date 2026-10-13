import Testing
@testable import SmarterThingsCore

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

    @Test func launchAndSearchDependOnSamsungCapabilities() {
        let tv = makeTV(["custom.launchapp", "custom.tvsearch"])
        #expect(tv.canLaunchApps && tv.canSearch)
        #expect(!makeTV(["switch"]).canLaunchApps)
        #expect(!makeTV(["switch"]).canSearch)
    }

    @Test func launchCommandSendsAppIDAndName() {
        #expect(TVCommand.launch(TVApp(id: "111299001912", name: "YouTube")) == TVCommand(
            capability: "custom.launchapp", command: "launchApp", arguments: ["111299001912", "YouTube"]
        ))
    }

    @Test func searchCommandSendsQueryWithEmptyURL() {
        // Confirmed on a 2025 Crystal UHD: an empty url shows Samsung search results.
        #expect(TVCommand.search("lofi music") == TVCommand(
            capability: "custom.tvsearch", command: "search", arguments: ["lofi music", ""]
        ))
    }

    private func makeTV(_ capabilities: Set<String>) -> TV {
        TV(id: "tv-1", name: "Living Room", capabilities: capabilities)
    }
}
