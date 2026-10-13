import Foundation

/// Wakes a TV from standby with a Wake-on-LAN "magic packet": six 0xFF bytes followed by
/// the MAC address 16 times, broadcast over UDP. Samsung TVs only listen for it when
/// "Power On with Mobile" is enabled in the TV's network settings.
public enum WakeOnLAN {
    public enum Failure: Error, Equatable {
        case invalidMACAddress
        case sendFailed
    }

    static let port: UInt16 = 9

    static func magicPacket(macAddress: String) -> [UInt8]? {
        let parts = macAddress.split(whereSeparator: { $0 == ":" || $0 == "-" })
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard parts.count == 6, bytes.count == 6 else { return nil }
        return Array(repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: bytes, count: 16).joined())
    }

    public static func wake(macAddress: String) async throws {
        guard let packet = magicPacket(macAddress: macAddress) else { throw Failure.invalidMACAddress }
        try await Task.detached { try broadcast(packet) }.value
    }

    private static func broadcast(_ packet: [UInt8]) throws {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { throw Failure.sendFailed }
        defer { close(socketDescriptor) }

        var enableBroadcast: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_BROADCAST, &enableBroadcast, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_BROADCAST

        let sent = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(socketDescriptor, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else { throw Failure.sendFailed }
    }
}
