import Testing
@testable import SmarterThingsCore

struct HIDReportQueueTests {
    private let pressA: [UInt8] = [0xA1, 0x01, 0, 0, 0x04, 0, 0, 0, 0, 0]
    private let release: [UInt8] = [0xA1, 0x01, 0, 0, 0, 0, 0, 0, 0, 0]
    private let pressB: [UInt8] = [0xA1, 0x01, 0, 0, 0x05, 0, 0, 0, 0, 0]

    @Test func firstReportIsWrittenImmediately() {
        var queue = HIDReportQueue()
        #expect(queue.enqueue(pressA) == pressA)
    }

    @Test func laterReportsWaitForTheWriteInFlight() {
        var queue = HIDReportQueue()
        _ = queue.enqueue(pressA)
        #expect(queue.enqueue(release) == nil)
        #expect(queue.inFlight == pressA)
    }

    @Test func completingAWriteSendsTheNextInOrder() {
        var queue = HIDReportQueue()
        _ = queue.enqueue(pressA)
        _ = queue.enqueue(release)
        _ = queue.enqueue(pressB)
        _ = queue.enqueue(release)

        #expect(queue.completeInFlight() == release)
        #expect(queue.completeInFlight() == pressB)
        #expect(queue.completeInFlight() == release)
        #expect(queue.completeInFlight() == nil)
        #expect(queue.inFlight == nil)
    }

    @Test func afterDrainingTheNextReportIsWrittenImmediately() {
        var queue = HIDReportQueue()
        _ = queue.enqueue(pressA)
        _ = queue.completeInFlight()
        #expect(queue.enqueue(release) == release)
    }

    @Test func resetDropsEverything() {
        var queue = HIDReportQueue()
        _ = queue.enqueue(pressA)
        _ = queue.enqueue(release)
        queue.reset()
        #expect(queue.inFlight == nil)
        #expect(queue.completeInFlight() == nil)
    }
}
