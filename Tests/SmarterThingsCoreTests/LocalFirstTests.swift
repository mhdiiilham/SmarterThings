import Testing
@testable import SmarterThingsCore

/// Behavior without a SmartThings token (no cloud TV), and the cloud as fallback only.
struct LocalFirstTests {
    private let cloudTV = TV(id: "tv-1", name: "TV", capabilities: ["custom.launchapp"])
    private let youTube = TVApp(id: "111299001912", name: "YouTube")

    // MARK: KeyDispatcher without a cloud TV

    @Test func withoutTokenKeysGoLocal() async throws {
        let dispatcher = KeyDispatcher(local: Presser(), cloud: Cloud(), localKeys: [.home])
        #expect(try await dispatcher.press(.home, on: nil) == .local)
    }

    @Test func withoutTokenALocalFailureIsReported() async {
        let dispatcher = KeyDispatcher(local: Presser(failure: LocalTVError.tvNotFound), cloud: Cloud(), localKeys: [.home])
        await #expect(throws: LocalTVError.tvNotFound) { try await dispatcher.press(.home, on: nil) }
    }

    @Test func withoutTokenAKeyWithNoLocalRouteFails() async {
        let dispatcher = KeyDispatcher(local: Presser(), cloud: Cloud(), localKeys: [])
        await #expect(throws: LocalTVError.unsupportedKey) { try await dispatcher.press(.powerOn, on: nil) }
    }

    // MARK: AppLauncher

    @Test func appsOpenLocallyFirst() async throws {
        let opener = Opener(), cloud = Cloud()
        try await AppLauncher(local: opener, cloud: cloud).open(youTube, cloudTV: cloudTV)
        #expect(await opener.opened == [youTube])
        #expect(await cloud.sent.isEmpty)
    }

    @Test func appsFallBackToTheCloudWithAToken() async throws {
        let cloud = Cloud()
        try await AppLauncher(local: Opener(failure: LocalTVError.tvNotFound), cloud: cloud).open(youTube, cloudTV: cloudTV)
        #expect(await cloud.sent == [.launch(youTube)])
    }

    @Test func appsFailWithoutLocalOrToken() async {
        let launcher = AppLauncher(local: Opener(failure: LocalTVError.tvNotFound), cloud: Cloud())
        await #expect(throws: LocalTVError.tvNotFound) { try await launcher.open(youTube, cloudTV: nil) }
    }

    // MARK: PowerControl

    @Test func powerStateComesFromTheTVFirst() async {
        let power = makePower(localState: .standby, cloud: Cloud(isOn: true))
        #expect(await power.isPoweredOn(cloudTV: cloudTV) == false)
    }

    @Test func unreachableTVWithoutTokenCountsAsOff() async {
        #expect(await makePower(localState: .unreachable).isPoweredOn(cloudTV: nil) == false)
    }

    @Test func unreachableTVAsksTheCloud() async {
        #expect(await makePower(localState: .unreachable, cloud: Cloud(isOn: true)).isPoweredOn(cloudTV: cloudTV) == true)
    }

    // MARK: Toggle decides from the TV's current state

    @Test func toggleTurnsOffATVThatIsOn() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(localState: .on, presser: presser, wake: { await woke.set() }).toggle(cloudTV: nil)
        #expect(isOn == false)
        #expect(await presser.pressed == [.powerOff])
        #expect(await !woke.isSet)
    }

    @Test func toggleTurnsOnATVInStandbyWithThePowerKey() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(localState: .standby, presser: presser, wake: { await woke.set() }).toggle(cloudTV: nil)
        #expect(isOn == true)
        #expect(await presser.pressed == [.powerOff])   // KEY_POWER toggles: wakes from standby
        #expect(await !woke.isSet)
    }

    @Test func toggleWakesAnUnreachableTVWithWakeOnLAN() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(localState: .unreachable, presser: presser, wake: { await woke.set() }).toggle(cloudTV: nil)
        #expect(isOn == true)
        #expect(await woke.isSet)
        #expect(await presser.pressed.isEmpty)
    }

    @Test func unreachableTVThatTheCloudSaysIsOnIsTurnedOffViaTheCloud() async throws {
        let cloud = Cloud(isOn: true)
        let isOn = try await makePower(localState: .unreachable, cloud: cloud).toggle(cloudTV: cloudTV)
        #expect(isOn == false)
        #expect(await cloud.sent == [RemoteKey.powerOff.command])
    }

    @Test func wakingFailsWithoutMACOrToken() async {
        let power = makePower(localState: .unreachable, wake: { throw WakeOnLAN.Failure.invalidMACAddress })
        await #expect(throws: WakeOnLAN.Failure.invalidMACAddress) { try await power.toggle(cloudTV: nil) }
    }

    @Test func wakingSucceedsWithATokenEvenWithoutMAC() async throws {
        let power = makePower(localState: .unreachable, wake: { throw WakeOnLAN.Failure.invalidMACAddress })
        #expect(try await power.toggle(cloudTV: cloudTV) == true)
    }

    private func makePower(
        localState: TVPowerState = .on,
        cloud: Cloud = Cloud(),
        presser: Presser = Presser(),
        wake: @escaping @Sendable () async throws -> Void = {}
    ) -> PowerControl {
        PowerControl(
            keys: KeyDispatcher(local: presser, cloud: cloud, localKeys: [.powerOff]),
            cloud: cloud,
            localPowerState: { localState },
            wake: wake
        )
    }
}

private actor Presser: TVKeyPresser {
    private let failure: Error?
    private(set) var pressed: [RemoteKey] = []
    init(failure: Error? = nil) { self.failure = failure }
    func prepare() async throws {}
    func press(_ key: RemoteKey) async throws {
        if let failure { throw failure }
        pressed.append(key)
    }
}

private actor Opener: TVAppOpener {
    private let failure: Error?
    private(set) var opened: [TVApp] = []
    init(failure: Error? = nil) { self.failure = failure }
    func open(_ app: TVApp) async throws {
        if let failure { throw failure }
        opened.append(app)
    }
}

private actor Cloud: TVController {
    private let isOn: Bool
    private(set) var sent: [TVCommand] = []
    init(isOn: Bool = false) { self.isOn = isOn }
    func televisions() async throws -> [TV] { [] }
    func inputSources(of tv: TV) async throws -> [InputSource] { [] }
    func isPoweredOn(_ tv: TV) async throws -> Bool { isOn }
    func send(_ command: TVCommand, to tv: TV) async throws { sent.append(command) }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}
