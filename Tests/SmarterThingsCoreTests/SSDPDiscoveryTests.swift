import Testing
@testable import SmarterThingsCore

struct SSDPDiscoveryTests {
    @Test func acceptsSamsungTVReply() {
        // Reply captured from a 2025 Samsung Crystal UHD (UA50UE100FKXXD).
        let reply = "HTTP/1.1 200 OK\r\nSERVER: Samsung-Linux/4.1, UPnP/1.0, Samsung_UPnP_SDK/1.0\r\n"
            + "ST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
        #expect(SSDPDiscovery.isSamsungReply(reply))
    }

    @Test func rejectsOtherDIALDevices() {
        let reply = "HTTP/1.1 200 OK\r\nSERVER: Linux/3.8.13+, UPnP/1.0, Portable SDK for UPnP devices\r\n"
            + "ST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
        #expect(!SSDPDiscovery.isSamsungReply(reply))
    }

    @Test func ignoresSamsungOutsideServerHeader() {
        let reply = "HTTP/1.1 200 OK\r\nSERVER: Linux, UPnP/1.0\r\nUSN: uuid:samsung-thing\r\n\r\n"
        #expect(!SSDPDiscovery.isSamsungReply(reply))
    }
}
