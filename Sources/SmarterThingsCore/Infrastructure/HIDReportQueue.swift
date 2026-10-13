/// Keeps keyboard reports in order with one write in flight at a time: the next report
/// goes out only after the previous write completes. Press→release order is what keeps
/// the TV from thinking a key is still held (and auto-repeating it).
struct HIDReportQueue {
    private var waiting: [[UInt8]] = []
    private(set) var inFlight: [UInt8]?

    /// Adds a report; returns it if it should be written now (nothing else in flight).
    mutating func enqueue(_ report: [UInt8]) -> [UInt8]? {
        guard inFlight == nil else {
            waiting.append(report)
            return nil
        }
        inFlight = report
        return report
    }

    /// Marks the in-flight write done; returns the next report to write, if any.
    mutating func completeInFlight() -> [UInt8]? {
        inFlight = waiting.isEmpty ? nil : waiting.removeFirst()
        return inFlight
    }

    mutating func reset() {
        waiting = []
        inFlight = nil
    }
}
