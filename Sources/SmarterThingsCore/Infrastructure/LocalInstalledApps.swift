import Foundation

/// Asks the TV about each known app with `GET http://<tv>:8001/api/v2/applications/<id>`:
/// 200 with the app's name if installed, 404 if not. Needs no pairing or "Allow" prompt.
/// (The TV has no cloud API for listing apps, and the WebSocket list request isn't reliable.)
public struct LocalInstalledApps: InstalledAppFinder, TVAppOpener {
    private let hostFinder: TVHostFinder
    private let transport: HTTPTransport

    public init(hostFinder: TVHostFinder, transport: HTTPTransport = URLSession.shared) {
        self.hostFinder = hostFinder
        self.transport = transport
    }

    public func installedApps(among candidates: [TVApp]) async throws -> [TVApp] {
        let host = try await hostFinder.host()
        let transport = transport
        let found = await withTaskGroup(of: (Int, TVApp?).self) { group in
            for (order, candidate) in candidates.enumerated() {
                group.addTask { (order, await Self.installedApp(candidate, host: host, transport: transport)) }
            }
            var found: [(Int, TVApp)] = []
            for await (order, app) in group {
                if let app { found.append((order, app)) }
            }
            return found
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// `POST` to the same endpoint opens the app; 404 means it isn't installed.
    public func open(_ app: TVApp) async throws {
        let host = try await hostFinder.host()
        let request = Self.openRequest(for: app, host: host)
        let (_, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw RemoteError.requestFailed(status: response.statusCode)
        }
    }

    static func openRequest(for app: TVApp, host: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://\(host):8001/api/v2/applications/\(app.id)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        return request
    }

    /// The TV's own name wins, e.g. it calls 3202010022079 "Browser".
    static func parseApplication(_ data: Data, statusCode: Int, candidate: TVApp) -> TVApp? {
        guard statusCode == 200,
              let info = try? JSONDecoder().decode(ApplicationInfo.self, from: data),
              info.id == candidate.id else { return nil }
        return TVApp(id: candidate.id, name: info.name ?? candidate.name)
    }

    private static func installedApp(_ candidate: TVApp, host: String, transport: HTTPTransport) async -> TVApp? {
        guard let url = URL(string: "http://\(host):8001/api/v2/applications/\(candidate.id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await transport.send(request) else { return nil }
        return parseApplication(data, statusCode: response.statusCode, candidate: candidate)
    }

    private struct ApplicationInfo: Decodable {
        let id: String
        let name: String?
    }
}
