/// The buttons of the remote. Each is sent to the TV as a Samsung key code
/// (see `LocalRemoteProtocol`), except `powerOn`, which is handled by `PowerControl`.
public enum RemoteKey: CaseIterable, Sendable {
    case powerOn, powerOff
    case volumeUp, volumeDown, mute, unmute
    case channelUp, channelDown
    case up, down, left, right, ok, back, home, menu
    case play, pause, stop, rewind, fastForward
    /// Opens the TV's input (source) menu.
    case source
}
