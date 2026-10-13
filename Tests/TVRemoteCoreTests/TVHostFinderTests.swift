import Testing
@testable import TVRemoteCore

struct TVHostFinderTests {
    private let livingRoom = LocalTVDevice(id: "uuid:living", name: "Living Room", host: "10.0.0.9")
    private let bedroom = LocalTVDevice(id: "uuid:bed", name: "Bedroom", host: "10.0.0.10")

    @Test func discoveryWinsSoAChangedIPIsPickedUp() async throws {
        let finder = TVHostFinder(manualHost: { "10.0.0.5" }, discover: { [livingRoom] })
        #expect(try await finder.host() == "10.0.0.9")
    }

    @Test func chosenTVIsMatchedByIDNotOrder() async throws {
        let finder = TVHostFinder(manualHost: { nil }, chosenDeviceID: { "uuid:bed" }, discover: { [livingRoom, bedroom] })
        #expect(try await finder.host() == "10.0.0.10")
    }

    @Test func usesFirstTVWhenNoneIsChosenOrTheChosenOneIsMissing() async throws {
        let finder = TVHostFinder(manualHost: { nil }, chosenDeviceID: { "uuid:gone" }, discover: { [livingRoom, bedroom] })
        #expect(try await finder.host() == "10.0.0.9")
    }

    @Test func manualHostIsTheFallbackWhenNothingIsDiscovered() async throws {
        let finder = TVHostFinder(manualHost: { "10.0.0.5" }, discover: { [] })
        #expect(try await finder.host() == "10.0.0.5")
    }

    @Test func throwsWhenNothingIsFound() async {
        let finder = TVHostFinder(manualHost: { "" }, discover: { [] })
        await #expect(throws: LocalTVError.tvNotFound) { try await finder.host() }
    }
}
