import Foundation
import Testing
@testable import SmarterThingsCore

struct LocalInstalledAppsTests {
    private let youTube = TVApp(id: "111299001912", name: "YouTube")
    private let browser = TVApp(id: "3202010022079", name: "Internet")
    private let notInstalled = TVApp(id: "9999999999999", name: "Nope")

    @Test func installedAppUsesTheTVsName() {
        // Response captured from a 2025 Crystal UHD.
        let body = #"{"id":"3202010022079","name":"Browser","running":true,"version":"1.0","visible":false}"#
        #expect(LocalInstalledApps.parseApplication(Data(body.utf8), statusCode: 200, candidate: browser)
            == TVApp(id: "3202010022079", name: "Browser"))
    }

    @Test func notFoundMeansNotInstalled() {
        let body = #"{"code":404,"message":"Not found error.","status":404}"#
        #expect(LocalInstalledApps.parseApplication(Data(body.utf8), statusCode: 404, candidate: notInstalled) == nil)
    }

    @Test func keepsOnlyInstalledAppsInCandidateOrder() async throws {
        let transport = RoutingTransport(routes: [
            "/api/v2/applications/111299001912": (200, #"{"id":"111299001912","name":"YouTube"}"#),
            "/api/v2/applications/3202010022079": (200, #"{"id":"3202010022079","name":"Browser"}"#),
        ])
        let finder = TVHostFinder(manualHost: { "192.168.0.223" }, discover: { [] })
        let apps = try await LocalInstalledApps(hostFinder: finder, transport: transport)
            .installedApps(among: [browser, notInstalled, youTube])

        #expect(apps.map(\.name) == ["Browser", "YouTube"])
    }
}

struct LocalAppOpeningTests {
    @Test func opensAnAppWithAPostToItsApplicationURL() {
        let request = LocalInstalledApps.openRequest(for: TVApp(id: "111299001912", name: "YouTube"), host: "192.168.0.223")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://192.168.0.223:8001/api/v2/applications/111299001912")
    }

    @Test func notInstalledAppFailsToOpen() async {
        let finder = TVHostFinder(manualHost: { "192.168.0.223" }, discover: { [] })
        let apps = LocalInstalledApps(hostFinder: finder, transport: RoutingTransport(routes: [:]))
        await #expect(throws: LocalTVError.requestFailed(status: 404)) {
            try await apps.open(TVApp(id: "9999999999999", name: "Nope"))
        }
    }
}

/// Answers by URL path (order-independent, for concurrent requests); unknown paths get 404.
private struct RoutingTransport: HTTPTransport {
    let routes: [String: (Int, String)]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = routes[request.url!.path] ?? (404, #"{"code":404}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
