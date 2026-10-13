import Foundation

/// Sends one SSDP M-SEARCH for Samsung TV remote receivers and collects who answers.
/// Plain BSD sockets: replies come from the TV's own address, not the multicast group.
public enum SSDPDiscovery {
    private static let multicastAddress = "239.255.255.250"
    private static let ssdpPort: UInt16 = 1900
    private static let searchTarget = "urn:samsung.com:device:RemoteControlReceiver:1"

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

        let request = Array("""
        M-SEARCH * HTTP/1.1\r
        HOST: \(multicastAddress):\(ssdpPort)\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: \(searchTarget)\r
        \r

        """.utf8)
        let sent = withUnsafePointer(to: &groupAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(socketDescriptor, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent >= 0 else { return [] }

        var hosts: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let host = receiveReplyHost(socketDescriptor), !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }

    private static func receiveReplyHost(_ socketDescriptor: Int32) -> String? {
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
        return String(cString: hostBuffer)
    }
}
