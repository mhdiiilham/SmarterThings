import Foundation
import Testing
@testable import SmarterThingsCore

struct KeyDispatcherTests {
    private let tv = TV(id: "tv-1", name: "TV", capabilities: [])

    @Test func localKeyGoesOverTheLocalNetwork() async throws {
        let local = FakeKeyPresser()
        let cloud = RecordingController()
        try await makeDispatcher(local, cloud).press(.up, on: tv)

        #expect(await local.pressed == [.up])
        #expect(await cloud.sent.isEmpty)
    }

    @Test func otherKeysAlwaysUseTheCloud() async throws {
        let local = FakeKeyPresser()
        let cloud = RecordingController()
        try await makeDispatcher(local, cloud).press(.home, on: tv)

        #expect(await local.pressed.isEmpty)
        #expect(await cloud.sent == [RemoteKey.home.command])
    }

    @Test func localFailureFallsBackToTheCloud() async throws {
        let local = FakeKeyPresser(failure: LocalTVError.tvNotFound)
        let cloud = RecordingController()
        try await makeDispatcher(local, cloud).press(.volumeUp, on: tv)

        #expect(await cloud.sent == [RemoteKey.volumeUp.command])
    }

    @Test func afterAFailureLocalIsSkippedUntilTheRetryInterval() async throws {
        let local = FakeKeyPresser(failure: LocalTVError.tvNotFound)
        let cloud = RecordingController()
        let clock = TestClock()
        let dispatcher = makeDispatcher(local, cloud, clock: clock)

        try await dispatcher.press(.up, on: tv)
        try await dispatcher.press(.down, on: tv)
        #expect(await local.attempts == 1)

        clock.advance(by: 61)
        try await dispatcher.press(.left, on: tv)
        #expect(await local.attempts == 2)
    }

    @Test func slowLocalConnectionUsesTheCloudWithoutGivingUpOnLocal() async throws {
        let local = FakeKeyPresser(delay: .milliseconds(300))
        let cloud = RecordingController()
        let dispatcher = makeDispatcher(local, cloud, timeout: .milliseconds(20))

        let route = try await dispatcher.press(.up, on: tv)
        #expect(route == .cloud)
        #expect(await cloud.sent == [RemoteKey.up.command])

        try await dispatcher.press(.down, on: tv)
        #expect(await local.attempts == 2)   // still tried locally, not paused
    }

    @Test func pressReportsTheRouteItTook() async throws {
        let dispatcher = makeDispatcher(FakeKeyPresser(), RecordingController())
        #expect(try await dispatcher.press(.ok, on: tv) == .local)
        #expect(try await dispatcher.press(.menu, on: tv) == .cloud)
    }

    @Test func warmUpOpensTheLocalConnection() async {
        let local = FakeKeyPresser()
        await makeDispatcher(local, RecordingController()).warmUp()
        #expect(await local.prepared)
    }

    private func makeDispatcher(
        _ local: FakeKeyPresser,
        _ cloud: RecordingController,
        clock: TestClock = TestClock(),
        timeout: Duration = .seconds(5)
    ) -> KeyDispatcher {
        KeyDispatcher(
            local: local,
            cloud: cloud,
            localKeys: [.up, .down, .left, .right, .ok, .volumeUp, .volumeDown],
            localTimeout: timeout,
            localRetryInterval: 60,
            now: { clock.now }
        )
    }
}

private actor FakeKeyPresser: TVKeyPresser {
    private let failure: Error?
    private let delay: Duration?
    private(set) var pressed: [RemoteKey] = []
    private(set) var attempts = 0
    private(set) var prepared = false

    init(failure: Error? = nil, delay: Duration? = nil) {
        self.failure = failure
        self.delay = delay
    }

    func prepare() async throws {
        prepared = true
    }

    func press(_ key: RemoteKey) async throws {
        attempts += 1
        if let delay { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        pressed.append(key)
    }
}

private actor RecordingController: TVController {
    private(set) var sent: [TVCommand] = []

    func televisions() async throws -> [TV] { [] }
    func inputSources(of tv: TV) async throws -> [InputSource] { [] }
    func isPoweredOn(_ tv: TV) async throws -> Bool { true }
    func send(_ command: TVCommand, to tv: TV) async throws { sent.append(command) }
}

private final class TestClock: @unchecked Sendable {
    private(set) var now = Date(timeIntervalSince1970: 0)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
