import Testing
@testable import SmarterThingsCore

/// Power decisions are made from the TV's current state, never a cached one.
struct PowerControlTests {
    @Test(arguments: [(TVPowerState.on, true), (.standby, false), (.unreachable, false)])
    func powerStateComesFromTheTV(state: TVPowerState, isOn: Bool) async {
        #expect(await makePower(state: state).isPoweredOn() == isOn)
    }

    @Test func toggleTurnsOffATVThatIsOn() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(state: .on, presser: presser, wake: { await woke.set() }).toggle()
        #expect(isOn == false)
        #expect(await presser.pressed == [.powerOff])
        #expect(await !woke.isSet)
    }

    @Test func toggleTurnsOnATVInStandbyWithThePowerKey() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(state: .standby, presser: presser, wake: { await woke.set() }).toggle()
        #expect(isOn == true)
        #expect(await presser.pressed == [.powerOff])
        #expect(await !woke.isSet)
    }

    @Test func toggleWakesAnUnreachableTVWithWakeOnLAN() async throws {
        let presser = Presser(), woke = Flag()
        let isOn = try await makePower(state: .unreachable, presser: presser, wake: { await woke.set() }).toggle()
        #expect(isOn == true)
        #expect(await woke.isSet)
        #expect(await presser.pressed.isEmpty)   // never KEY_POWER to a TV that isn't listening
    }

    @Test func wakingFailsWithoutAKnownMACAddress() async {
        let power = makePower(state: .unreachable, wake: { throw WakeOnLAN.Failure.invalidMACAddress })
        await #expect(throws: WakeOnLAN.Failure.invalidMACAddress) { try await power.toggle() }
    }

    private func makePower(
        state: TVPowerState,
        presser: Presser = Presser(),
        wake: @escaping @Sendable () async throws -> Void = {}
    ) -> PowerControl {
        PowerControl(keys: presser, localPowerState: { state }, wake: wake)
    }
}

private actor Presser: TVKeyPresser {
    private(set) var pressed: [RemoteKey] = []
    func prepare() async throws {}
    func press(_ key: RemoteKey) async throws { pressed.append(key) }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}
