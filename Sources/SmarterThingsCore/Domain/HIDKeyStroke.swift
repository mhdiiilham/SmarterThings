/// Modifier keys in a USB/Bluetooth HID keyboard report (left-hand keys).
public struct HIDModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = HIDModifiers(rawValue: 0x01)
    public static let shift = HIDModifiers(rawValue: 0x02)
    public static let option = HIDModifiers(rawValue: 0x04)
    public static let command = HIDModifiers(rawValue: 0x08)
}

/// One key press as a keyboard sends it: a HID usage code (Keyboard page 0x07) plus modifiers.
public struct HIDKeyStroke: Hashable, Sendable {
    public let usage: UInt8
    public let modifiers: HIDModifiers

    public init(usage: UInt8, modifiers: HIDModifiers = []) {
        self.usage = usage
        self.modifiers = modifiers
    }
}

/// Port for sending real keystrokes to the TV, e.g. as a Bluetooth keyboard.
/// Unlike typing into Samsung's on-screen keyboard, this works in apps like YouTube and Netflix.
public protocol KeystrokeSender: Sendable {
    func send(_ stroke: HIDKeyStroke) async throws
}
