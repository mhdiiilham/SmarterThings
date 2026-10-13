import Foundation
import Testing
@testable import SmarterThingsCore

struct HIDKeyboardProtocolTests {
    @Test func keyPressReportCarriesModifiersAndUsage() {
        let shiftA = HIDKeyStroke(usage: 0x04, modifiers: .shift)
        #expect(HIDKeyboardProtocol.inputReport(shiftA) == [0xA1, 0x01, 0x02, 0x00, 0x04, 0, 0, 0, 0, 0])
    }

    @Test func releaseReportHasNoKeys() {
        #expect(HIDKeyboardProtocol.inputReport(nil) == [0xA1, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0])
    }

    @Test(arguments: [
        ([UInt8(0x70)], [UInt8(0x00)]),     // SET_PROTOCOL boot -> success
        ([0x71], [0x00]),                   // SET_PROTOCOL report -> success
        ([0x90, 0x00], [0x00]),             // SET_IDLE -> success
        ([0x60], [0xA0, 0x01]),             // GET_PROTOCOL -> report protocol
        ([0x80], [0xA0, 0x00]),             // GET_IDLE -> infinite
        ([0x30], [0x03]),                   // reserved type -> unsupported
    ])
    func answersControlRequests(message: [UInt8], reply: [UInt8]) {
        #expect(HIDKeyboardProtocol.controlReply(to: message) == reply)
    }

    @Test func getReportReturnsAnEmptyKeyboardReport() {
        #expect(HIDKeyboardProtocol.controlReply(to: [0x41, 0x01]) == HIDKeyboardProtocol.inputReport(nil))
    }

    @Test(arguments: [[UInt8(0x15)], [0xA2, 0x01, 0x02], []])
    func doesNotAnswerControlOperationsOrOutputData(message: [UInt8]) {
        #expect(HIDKeyboardProtocol.controlReply(to: message) == nil)
    }

    @Test func reportDescriptorIsABalancedKeyboardCollection() {
        let descriptor = HIDKeyboardProtocol.reportDescriptor
        #expect(Array(descriptor.prefix(4)) == [0x05, 0x01, 0x09, 0x06])   // Generic Desktop, Keyboard
        #expect(descriptor.last == 0xC0)                                    // End Collection
    }

    @Test func serviceRecordAdvertisesAKeyboardOnTheHIDChannels() throws {
        let record = HIDKeyboardProtocol.serviceRecord(serviceName: "SmarterThings Keyboard")
        #expect(record["0001 - ServiceClassIDList"] as? [Data] == [Data([0x11, 0x24])])
        #expect(record["0100 - ServiceName"] as? String == "SmarterThings Keyboard")
        let subclass = try #require(record["0202 - HIDDeviceSubclass"] as? [String: Any])
        #expect(subclass["DataElementValue"] as? Data == Data([0x40]))
        let descriptors = try #require(record["0206 - HIDDescriptorList"] as? [[Any]])
        let descriptor = try #require(descriptors.first?.last as? [String: Any])
        #expect(descriptor["DataElementValue"] as? Data == Data(HIDKeyboardProtocol.reportDescriptor))
    }
}

struct MacKeyCodeMapTests {
    @Test(arguments: [
        (UInt16(0x00), UInt8(0x04)),   // a
        (0x06, 0x1D),                  // z
        (0x12, 0x1E),                  // 1
        (0x1D, 0x27),                  // 0
        (0x31, 0x2C),                  // space
        (0x24, 0x28),                  // return
        (0x33, 0x2A),                  // delete (backspace)
        (0x7E, 0x52),                  // up arrow
        (0x7B, 0x50),                  // left arrow
    ])
    func mapsMacKeyCodesToHIDUsages(keyCode: UInt16, usage: UInt8) {
        #expect(MacKeyCodeMap.stroke(forKeyCode: keyCode, modifiers: []) == HIDKeyStroke(usage: usage))
    }

    @Test func keepsModifiers() {
        #expect(MacKeyCodeMap.stroke(forKeyCode: 0x00, modifiers: .shift)?.modifiers == .shift)
    }

    @Test func unknownKeysAreIgnored() {
        #expect(MacKeyCodeMap.stroke(forKeyCode: 0x3F, modifiers: []) == nil)   // fn
    }
}
