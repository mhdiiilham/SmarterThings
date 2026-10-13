/// One SmartThings device command, e.g. `switch` → `on`.
public struct TVCommand: Equatable, Sendable {
    public let capability: String
    public let command: String
    public let arguments: [String]

    public init(capability: String, command: String, arguments: [String] = []) {
        self.capability = capability
        self.command = command
        self.arguments = arguments
    }
}

extension TVCommand {
    /// Opens an app through SmartThings; the name is a fallback if the ID is unknown to the TV.
    public static func launch(_ app: TVApp) -> TVCommand {
        TVCommand(capability: "custom.launchapp", command: "launchApp", arguments: [app.id, app.name])
    }

    /// Runs the TV's own search (Samsung's universal search) for `query`.
    public static func search(_ query: String) -> TVCommand {
        TVCommand(capability: "custom.tvsearch", command: "search", arguments: [query, ""])
    }
}
