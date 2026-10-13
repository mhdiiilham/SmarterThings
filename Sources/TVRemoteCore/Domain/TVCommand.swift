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
