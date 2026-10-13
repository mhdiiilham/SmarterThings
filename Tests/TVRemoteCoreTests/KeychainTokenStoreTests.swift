import Testing
@testable import TVRemoteCore

struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "com.mo.TVRemote.tests")

    @Test func savesReplacesAndClearsToken() throws {
        defer { try? store.clear() }

        try store.save("first")
        try store.save("second")
        #expect(store.token() == "second")

        try store.clear()
        #expect(store.token() == nil)
    }
}
