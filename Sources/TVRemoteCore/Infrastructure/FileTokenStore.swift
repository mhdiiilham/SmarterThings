import Foundation

/// Stores a token in a file only the current user can read (folder 0700, file 0600).
/// Chosen over the Keychain because the ad-hoc signed app is a "new app" to the
/// Keychain after every rebuild, which made it ask for the password again.
public struct FileTokenStore: TokenStore {
    private let fileURL: URL

    public init(name: String, directory: URL = Self.defaultDirectory) {
        fileURL = directory.appending(path: name)
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TVRemote")
    }

    public func token() -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    public func save(_ token: String) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(token.utf8).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
