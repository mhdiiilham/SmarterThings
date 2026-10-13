import Foundation
import Testing
@testable import TVRemoteCore

struct FileTokenStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "TVRemoteTests-\(UUID())")
    private var store: FileTokenStore { FileTokenStore(name: "token", directory: directory) }

    @Test func missingFileMeansNoToken() {
        #expect(store.token() == nil)
    }

    @Test func savesReplacesAndClearsToken() throws {
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save("first")
        try store.save("second")
        #expect(store.token() == "second")

        try store.clear()
        #expect(store.token() == nil)
    }

    @Test func onlyTheOwnerCanReadTheToken() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save("secret")

        #expect(try permissions(of: directory) == 0o700)
        #expect(try permissions(of: directory.appending(path: "token")) == 0o600)
    }

    private func permissions(of url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }
}
