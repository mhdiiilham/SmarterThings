import Testing
@testable import SmarterThingsCore

struct WakeOnLANTests {
    @Test func magicPacketIsSyncBytesThenTheMACSixteenTimes() throws {
        let packet = try #require(WakeOnLAN.magicPacket(macAddress: "CC:20:AC:5E:4A:E1"))
        #expect(packet.count == 102)
        #expect(Array(packet.prefix(6)) == [UInt8](repeating: 0xFF, count: 6))
        let mac: [UInt8] = [0xCC, 0x20, 0xAC, 0x5E, 0x4A, 0xE1]
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            #expect(Array(packet[start..<start + 6]) == mac)
        }
    }

    @Test func acceptsDashSeparatedAddresses() {
        #expect(WakeOnLAN.magicPacket(macAddress: "cc-20-ac-5e-4a-e1") == WakeOnLAN.magicPacket(macAddress: "CC:20:AC:5E:4A:E1"))
    }

    @Test(arguments: ["", "CC:20:AC", "CC:20:AC:5E:4A:ZZ", "CC:20:AC:5E:4A:E1:00"])
    func rejectsInvalidAddresses(macAddress: String) {
        #expect(WakeOnLAN.magicPacket(macAddress: macAddress) == nil)
    }
}
