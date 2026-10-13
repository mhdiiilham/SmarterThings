import Foundation

/// Finds Samsung TVs with SSDP M-SEARCH and collects the addresses that answer.
/// Plain BSD sockets: replies come from the TV's own address, not the multicast group.
public enum SSDPDiscovery {
    private static let multicastAddress = "239.255.255.250"
    private static let ssdpPort: UInt16 = 1900
    /// Older TVs answer the Samsung remote target; newer ones (e.g. 2025 models) only answer DIAL.
    private static let searchTargets = [
        "urn:samsung.com:device:RemoteControlReceiver:1",
        "urn:dial-multiscreen-org:service:dial:1",
    ]

    /// Chromecasts and other streaming devices answer DIAL too; keep only Samsung's UPnP stack.
    static func isSamsungReply(_ reply: String) -> Bool {
        reply.split(whereSeparator: \.isNewline).contains { line in
            line.lowercased().hasPrefix("server:") && line.localizedCaseInsensitiveContains("samsung")
        }
    }

    public static func samsungTVHosts(timeout: TimeInterval = 3) async -> [String] {
        await Task.detached { search(timeout: timeout) }.value
    }

    private static func search(timeout: TimeInterval) -> [String] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { return [] }
        defer { close(socketDescriptor) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var groupAddress = sockaddr_in()
        groupAddress.sin_family = sa_family_t(AF_INET)
        groupAddress.sin_port = ssdpPort.bigEndian
        inet_pton(AF_INET, multicastAddress, &groupAddress.sin_addr)

        let sentCount = searchTargets.filter { target in
            let request = Array("""
            M-SEARCH * HTTP/1.1\r
            HOST: \(multicastAddress):\(ssdpPort)\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: \(target)\r
            \r

            """.utf8)
            return withUnsafePointer(to: &groupAddress) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketDescriptor, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            } >= 0
        }.count
        guard sentCount > 0 else { return [] }

        var hosts: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let reply = receiveReply(socketDescriptor), isSamsungReply(reply.text), !hosts.contains(reply.host) {
                hosts.append(reply.host)
            }
        }
        return hosts
    }

    private static func receiveReply(_ socketDescriptor: Int32) -> (host: String, text: String)? {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var sender = sockaddr_in()
        var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &sender) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(socketDescriptor, &buffer, buffer.count, 0, $0, &senderLength)
            }
        }
        guard received > 0 else { return nil }
        var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &sender.sin_addr, &hostBuffer, socklen_t(INET_ADDRSTRLEN))
        let hostBytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let text = String(decoding: buffer.prefix(received), as: UTF8.self)
        return (String(decoding: hostBytes, as: UTF8.self), text)
    }
}
