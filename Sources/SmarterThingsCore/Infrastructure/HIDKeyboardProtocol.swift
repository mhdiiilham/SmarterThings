import Foundation

/// The Bluetooth HID Profile pieces for acting as a keyboard: the report descriptor,
/// key reports, replies on the control channel and the SDP service record.
/// Values follow the Bluetooth HID Profile and USB HID specifications.
enum HIDKeyboardProtocol {
    static let controlPSM: UInt16 = 0x0011
    static let interruptPSM: UInt16 = 0x0013
    /// Major class Peripheral, minor class Keyboard, plus "limited discoverable".
    static let keyboardClassOfDevice: UInt32 = 0x002540
    static let keyboardReportID: UInt8 = 0x01

    /// The HID spec's boot keyboard (Appendix B.1) with report ID 1:
    /// modifiers, a reserved byte, 5 LED outputs and 6 key slots.
    static let reportDescriptor: [UInt8] = [
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x85, keyboardReportID,
        0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
        0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
        0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02,
        0x95, 0x01, 0x75, 0x03, 0x91, 0x01,
        0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00,
        0xC0,
    ]

    // HIDP transaction headers (high nibble = type, low nibble = parameter).
    private static let dataInput: UInt8 = 0xA1
    private static let handshakeSuccessful: UInt8 = 0x00
    private static let handshakeUnsupported: UInt8 = 0x03

    /// Interrupt-channel message for keys held down; `nil` means all keys released.
    static func inputReport(_ stroke: HIDKeyStroke?) -> [UInt8] {
        let modifiers = stroke?.modifiers.rawValue ?? 0
        let key = stroke?.usage ?? 0
        return [dataInput, keyboardReportID, modifiers, 0x00, key, 0x00, 0x00, 0x00, 0x00, 0x00]
    }

    /// What to answer on the control channel, or `nil` when no answer is expected.
    static func controlReply(to message: [UInt8]) -> [UInt8]? {
        guard let header = message.first else { return nil }
        switch header >> 4 {
        case 0x1: return nil                                    // HID_CONTROL (e.g. virtual cable unplug)
        case 0x4: return inputReport(nil)                        // GET_REPORT: current (empty) report
        case 0x6: return [0xA0, 0x01]                            // GET_PROTOCOL: report protocol
        case 0x8: return [0xA0, 0x00]                            // GET_IDLE: infinite
        case 0x5, 0x7, 0x9: return [handshakeSuccessful]         // SET_REPORT, SET_PROTOCOL, SET_IDLE
        case 0xA: return nil                                     // DATA (e.g. LED output report)
        default: return [handshakeUnsupported]
        }
    }

    /// SDP record in IOBluetooth's dictionary format: keys start with the attribute ID in hex,
    /// 2-byte `Data` values in sequences are UUIDs, typed numbers use DataElementType 1.
    static func serviceRecord(serviceName: String) -> [String: Any] {
        let l2cap = uuid(0x0100), hidp = uuid(0x0011), humanInterfaceDevice = uuid(0x1124)
        return [
            "0001 - ServiceClassIDList": [humanInterfaceDevice],
            "0004 - ProtocolDescriptorList": [[l2cap, uint16(controlPSM)], [hidp]],
            "0005 - BrowseGroupList": [uuid(0x1002)],
            "0006 - LanguageBaseAttributeIDList": [uint16(0x656E), uint16(0x006A), uint16(0x0100)],
            "0009 - BluetoothProfileDescriptorList": [[humanInterfaceDevice, uint16(0x0101)]],
            "000D - AdditionalProtocolDescriptorLists": [[[l2cap, uint16(interruptPSM)], [hidp]]],
            "0100 - ServiceName": serviceName,
            "0101 - ServiceDescription": "Keyboard",
            "0102 - ProviderName": "SmarterThings",
            "0201 - HIDParserVersion": uint16(0x0111),
            "0202 - HIDDeviceSubclass": uint8(0x40),
            "0203 - HIDCountryCode": uint8(0x00),
            "0204 - HIDVirtualCable": true,
            "0205 - HIDReconnectInitiate": true,
            "0206 - HIDDescriptorList": [[uint8(0x22), ["DataElementType": 4, "DataElementValue": Data(reportDescriptor)]]],
            "0207 - HIDLANGIDBaseList": [[uint16(0x0409), uint16(0x0100)]],
            "0209 - HIDBatteryPower": true,
            "020A - HIDRemoteWake": true,
            "020B - HIDProfileVersion": uint16(0x0101),
            "020C - HIDSupervisionTimeout": uint16(0x0C80),
            "020D - HIDNormallyConnectable": true,
            "020E - HIDBootDevice": true,
        ]
    }

    private static func uuid(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 0xFF)]) }

    private static func uint8(_ value: UInt8) -> [String: Any] {
        ["DataElementType": 1, "DataElementSize": 1, "DataElementValue": Data([value])]
    }

    private static func uint16(_ value: UInt16) -> [String: Any] {
        ["DataElementType": 1, "DataElementSize": 2, "DataElementValue": uuid(value)]
    }
}
