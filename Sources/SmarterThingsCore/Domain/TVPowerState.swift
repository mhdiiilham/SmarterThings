/// What the TV reports about itself on the local network.
public enum TVPowerState: Sendable, Equatable {
    case on
    /// Screen off but still on the network, listening for the power key.
    case standby
    /// No answer: deep off, unplugged, or not on this network.
    case unreachable
}
