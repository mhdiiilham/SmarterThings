import Foundation

/// Finds Samsung TVs with SSDP, then asks each one who it is via http://<host>:8001/api/v2/.
public enum LocalTVDiscovery {
    public static func devices(transport: HTTPTransport = URLSession.shared) async -> [LocalTVDevice] {
        let hosts = await SSDPDiscovery.samsungTVHosts()
        return await withTaskGroup(of: LocalTVDevice?.self) { group in
            for host in hosts {
                group.addTask { await device(at: host, transport: transport) }
            }
            var devices: [LocalTVDevice] = []
            for await device in group {
                if let device { devices.append(device) }
            }
            return devices.sorted { $0.name < $1.name }
        }
    }

    static func parseDeviceInfo(_ data: Data, host: String) -> LocalTVDevice? {
        guard let info = try? JSONDecoder().decode(DeviceInfo.self, from: data),
              info.device.type == "Samsung SmartTV" else { return nil }
        return LocalTVDevice(
            id: info.device.id,
            name: decodeHTMLEntities(info.device.name),
            host: host,
            macAddress: info.device.wifiMac
        )
    }

    /// What the TV at `host` reports: `on`, `standby` (screen off, still listening), or
    /// `unreachable` when it doesn't answer.
    public static func powerState(host: String, transport: HTTPTransport = URLSession.shared) async -> TVPowerState {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return .unreachable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await transport.send(request), response.statusCode == 200 else {
            return .unreachable
        }
        return parsePowerState(data)
    }

    static func parsePowerState(_ data: Data) -> TVPowerState {
        guard let info = try? JSONDecoder().decode(DeviceInfo.self, from: data) else { return .unreachable }
        // Older firmware has no PowerState; answering at all means it's on.
        return (info.device.PowerState ?? "on").lowercased() == "on" ? .on : .standby
    }

    private static func device(at host: String, transport: HTTPTransport) async -> LocalTVDevice? {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, response) = try? await transport.send(request), response.statusCode == 200 else { return nil }
        return parseDeviceInfo(data, host: host)
    }

    /// The TV escapes its name for HTML, e.g. `50&quot; Crystal UHD`.
    private static func decodeHTMLEntities(_ text: String) -> String {
        [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private struct DeviceInfo: Decodable {
        let device: Device

        struct Device: Decodable {
            let id: String
            let name: String
            let type: String
            let wifiMac: String?
            let PowerState: String?
        }
    }
}
