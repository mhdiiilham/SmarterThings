import Foundation
import Testing
@testable import SmarterThingsCore

struct LocalTVDiscoveryTests {
    @Test func parsesTVInfoAndUnescapesName() {
        // Shape of http://<tv>:8001/api/v2/ from a 2025 Samsung Crystal UHD.
        let info = #"""
        {"device": {"id": "uuid:78e53199-eb25-4dda-9e10-4fb18f040034",
                    "name": "50&quot; Crystal UHD", "type": "Samsung SmartTV", "OS": "Tizen"},
         "id": "uuid:78e53199-eb25-4dda-9e10-4fb18f040034", "type": "Samsung SmartTV"}
        """#
        #expect(LocalTVDiscovery.parseDeviceInfo(Data(info.utf8), host: "192.168.0.223") == LocalTVDevice(
            id: "uuid:78e53199-eb25-4dda-9e10-4fb18f040034", name: "50\" Crystal UHD", host: "192.168.0.223"
        ))
    }

    @Test func rejectsNonTVDevices() {
        let info = #"{"device": {"id": "uuid:1", "name": "Soundbar", "type": "Samsung Speaker"}}"#
        #expect(LocalTVDiscovery.parseDeviceInfo(Data(info.utf8), host: "10.0.0.2") == nil)
    }

    @Test func rejectsUnexpectedJSON() {
        #expect(LocalTVDiscovery.parseDeviceInfo(Data("<html>".utf8), host: "10.0.0.2") == nil)
    }
}
