public struct TV: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let capabilities: Set<String>

    public init(id: String, name: String, capabilities: Set<String>) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }

    /// SmartThings has no "TV" device type; Samsung TVs are recognized by their TV-only capabilities.
    public var isTelevision: Bool {
        !capabilities.isDisjoint(with: ["samsungvd.remoteControl", "tvChannel"])
    }

    public func supports(_ key: RemoteKey) -> Bool {
        capabilities.contains(key.command.capability)
    }

    /// Newer TVs expose Samsung's own input capability with friendly names; prefer it.
    public var inputSourceCapability: String? {
        ["samsungvd.mediaInputSource", "mediaInputSource"].first(where: capabilities.contains)
    }

    public func selectInputCommand(_ source: InputSource) -> TVCommand? {
        guard let inputSourceCapability else { return nil }
        return TVCommand(capability: inputSourceCapability, command: "setInputSource", arguments: [source.id])
    }
}

public struct InputSource: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
