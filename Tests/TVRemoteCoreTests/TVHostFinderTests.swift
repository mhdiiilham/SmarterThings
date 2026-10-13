import Testing
@testable import TVRemoteCore

struct TVHostFinderTests {
    @Test func discoveryWinsSoAChangedIPIsPickedUp() async throws {
        let finder = TVHostFinder(manualHost: { "10.0.0.5" }, discover: { ["10.0.0.9"] })
        #expect(try await finder.host() == "10.0.0.9")
    }

    @Test func manualHostIsTheFallbackWhenNothingIsDiscovered() async throws {
        let finder = TVHostFinder(manualHost: { "10.0.0.5" }, discover: { [] })
        #expect(try await finder.host() == "10.0.0.5")
    }

    @Test func usesFirstDiscoveredHostWhenNoManualHost() async throws {
        let finder = TVHostFinder(manualHost: { nil }, discover: { ["10.0.0.9", "10.0.0.10"] })
        #expect(try await finder.host() == "10.0.0.9")
    }

    @Test func throwsWhenNothingIsFound() async {
        let finder = TVHostFinder(manualHost: { "" }, discover: { [] })
        await #expect(throws: LocalTVError.tvNotFound) { try await finder.host() }
    }
}
