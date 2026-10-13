import Foundation
import IOBluetooth
import OSLog

private let bluetoothLog = Logger(subsystem: "com.mhdiiilham.SmarterThings", category: "bluetooth")

/// Makes the Mac act as a Bluetooth keyboard for the TV (classic Bluetooth HID):
/// publishes a keyboard SDP record, presents the Mac as a keyboard, connects to the TV
/// and sends key reports on the HID interrupt channel. The TV must have been paired once;
/// macOS shows the pairing-code dialog during the first connection.
@MainActor
public final class BluetoothHIDKeyboard: NSObject, KeystrokeSender {
    public enum Failure: Error, Equatable {
        case bluetoothUnavailable
        case notConnected
        /// IOKit result codes from IOBluetooth, for diagnosis.
        case connectionFailed(IOReturn)
        case channelFailed(psm: UInt16, IOReturn)
        case writeFailed(IOReturn)
    }

    public private(set) var connectedDeviceName: String?
    /// Called on the main thread when the TV drops the connection.
    public var onDisconnect: (() -> Void)?

    private let serviceName: String
    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var device: IOBluetoothDevice?
    private var controlChannel: IOBluetoothL2CAPChannel?
    private var interruptChannel: IOBluetoothL2CAPChannel?
    /// Key reports wait here so they go out strictly in order, one write at a time.
    private var reportQueue = HIDReportQueue()
    /// The in-flight report's bytes. `writeAsync` reads them after returning, so they must
    /// stay allocated until `l2capChannelWriteComplete` (freeing them early dropped key-ups,
    /// which made the TV auto-repeat the key).
    private var inFlightBuffer: UnsafeMutableRawPointer?
    private var releaseRetries = 0
    private let maxReleaseRetries = 3
    // Pending async opens, resumed from IOBluetooth's callbacks on the main run loop.
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var channelContinuations: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]

    public init(serviceName: String = "SmarterThings Keyboard") {
        self.serviceName = serviceName
    }

    public var isConnected: Bool { interruptChannel != nil }

    /// Bluetooth address of a previously chosen TV, e.g. "a1-b2-c3-d4-e5-f6".
    public func connect(toAddress address: String) async throws {
        guard let device = IOBluetoothDevice(addressString: address) else { throw Failure.notConnected }
        try await connect(to: device)
    }

    /// Asynchronous so the UI stays responsive while the TV accepts (and, the first time, pairs).
    public func connect(to device: IOBluetoothDevice) async throws {
        disconnect()
        try publishServiceRecordIfNeeded()
        presentAsKeyboard()

        let name = device.name ?? device.addressString ?? "device"
        bluetoothLog.info("connecting to \(name, privacy: .public); already connected: \(device.isConnected(), privacy: .public)")
        try await openBasebandConnection(to: device)
        self.device = device

        do {
            controlChannel = try await openChannelRetryingOnce(on: device, psm: HIDKeyboardProtocol.controlPSM)
            interruptChannel = try await openChannelRetryingOnce(on: device, psm: HIDKeyboardProtocol.interruptPSM)
            bluetoothLog.info("HID channels open to \(name, privacy: .public)")
        } catch {
            bluetoothLog.error("connect to \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            disconnect()
            throw error
        }
        connectedDeviceName = device.name ?? device.addressString
    }

    public func disconnect() {
        reportQueue.reset()
        freeInFlightBuffer()
        interruptChannel?.close()
        controlChannel?.close()
        interruptChannel = nil
        controlChannel = nil
        device?.closeConnection()
        device = nil
        connectedDeviceName = nil
    }

    /// Presses and releases one key.
    public func send(_ stroke: HIDKeyStroke) async throws {
        guard interruptChannel != nil else { throw Failure.notConnected }
        enqueue(HIDKeyboardProtocol.inputReport(stroke))
        enqueue(HIDKeyboardProtocol.inputReport(nil))
    }

    /// Sends a key-up for everything, e.g. when typing stops, so no key is left held.
    public func releaseAllKeys() {
        guard interruptChannel != nil else { return }
        enqueue(HIDKeyboardProtocol.inputReport(nil))
    }

    private func enqueue(_ report: [UInt8]) {
        if let now = reportQueue.enqueue(report) { startWrite(now) }
    }

    private func startWrite(_ report: [UInt8]) {
        guard let channel = interruptChannel else {
            reportQueue.reset()
            return
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: report.count, alignment: 1)
        buffer.copyMemory(from: report, byteCount: report.count)
        inFlightBuffer = buffer
        let result = channel.writeAsync(buffer, length: UInt16(report.count), refcon: nil)
        if result != kIOReturnSuccess {
            finishWrite(status: result)
        }
    }

    /// Frees the finished report and starts the next. Every press is already followed by a
    /// queued release, so a key can only stick if a release fails; that one is retried.
    private func finishWrite(status: IOReturn) {
        freeInFlightBuffer()
        let finished = reportQueue.inFlight
        if status != kIOReturnSuccess {
            bluetoothLog.error("key report write failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public)")
            if let finished, finished == HIDKeyboardProtocol.inputReport(nil), releaseRetries < maxReleaseRetries {
                releaseRetries += 1
                startWrite(finished)
                return
            }
        }
        releaseRetries = 0
        if let next = reportQueue.completeInFlight() { startWrite(next) }
    }

    private func freeInFlightBuffer() {
        inFlightBuffer?.deallocate()
        inFlightBuffer = nil
    }

    private func publishServiceRecordIfNeeded() throws {
        guard serviceRecord == nil else { return }
        let record = HIDKeyboardProtocol.serviceRecord(serviceName: serviceName)
        guard let published = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: record) else {
            throw Failure.bluetoothUnavailable
        }
        serviceRecord = published
    }

    /// The TV checks the class of device; macOS restores the Mac's own class afterwards.
    private func presentAsKeyboard() {
        _ = IOBluetoothHostController.default()?.setClassOfDevice(
            HIDKeyboardProtocol.keyboardClassOfDevice, forTimeInterval: 120
        )
    }

    private func openBasebandConnection(to device: IOBluetoothDevice) async throws {
        guard !device.isConnected() else { return }
        try await withCheckedThrowingContinuation { continuation in
            connectionContinuation = continuation
            let result = device.openConnection(self)
            if result != kIOReturnSuccess {
                connectionContinuation = nil
                continuation.resume(throwing: Failure.connectionFailed(result))
            }
        }
    }

    /// A channel can be refused while the link is still authenticating; one retry after a
    /// short pause usually gets through.
    private func openChannelRetryingOnce(on device: IOBluetoothDevice, psm: UInt16) async throws -> IOBluetoothL2CAPChannel {
        do {
            return try await openChannel(on: device, psm: psm)
        } catch {
            bluetoothLog.notice("PSM 0x\(String(psm, radix: 16), privacy: .public) failed (\(String(describing: error), privacy: .public)); retrying")
            try await Task.sleep(for: .seconds(1))
            return try await openChannel(on: device, psm: psm)
        }
    }

    private func openChannel(on device: IOBluetoothDevice, psm: UInt16) async throws -> IOBluetoothL2CAPChannel {
        var channel: IOBluetoothL2CAPChannel?
        let result = device.openL2CAPChannelAsync(&channel, withPSM: psm, delegate: self)
        guard result == kIOReturnSuccess, let channel else { throw Failure.channelFailed(psm: psm, result) }
        // The completion callback runs on the main run loop, so it can't fire before this is stored.
        try await withCheckedThrowingContinuation { continuation in
            channelContinuations[ObjectIdentifier(channel)] = continuation
        }
        return channel
    }

    /// `writeAsync` copies the bytes into IOBluetooth's buffer and returns at once, so typing
    /// never waits on the radio (`writeSync` blocked the main thread until each report was sent).
    /// Control-channel replies are rare and short, so a synchronous write is fine here.
    private func writeControlReply(_ bytes: [UInt8]) {
        guard let channel = controlChannel else { return }
        var buffer = bytes
        let result = buffer.withUnsafeMutableBytes { pointer in
            channel.writeSync(pointer.baseAddress, length: UInt16(pointer.count))
        }
        if result != kIOReturnSuccess {
            bluetoothLog.error("control reply failed: 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
        }
    }

    deinit {
        MainActor.assumeIsolated {
            disconnect()
            serviceRecord?.remove()
        }
    }
}

// IOBluetooth calls these on the main run loop.
extension BluetoothHIDKeyboard: IOBluetoothL2CAPChannelDelegate {
    /// Target callback of `IOBluetoothDevice.openConnection(_:)`.
    @objc nonisolated public func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        MainActor.assumeIsolated {
            let continuation = connectionContinuation
            connectionContinuation = nil
            if status == kIOReturnSuccess {
                continuation?.resume()
            } else {
                continuation?.resume(throwing: Failure.connectionFailed(status))
            }
        }
    }

    /// The previous `writeAsync` finished; its buffer can be freed and the next report sent.
    nonisolated public func l2capChannelWriteComplete(
        _ l2capChannel: IOBluetoothL2CAPChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        let channelID = ObjectIdentifier(l2capChannel)
        MainActor.assumeIsolated {
            guard channelID == interruptChannel.map(ObjectIdentifier.init) else { return }
            finishWrite(status: error)
        }
    }

    nonisolated public func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        let channelID = ObjectIdentifier(l2capChannel)
        let psm = l2capChannel.psm
        MainActor.assumeIsolated {
            let continuation = channelContinuations.removeValue(forKey: channelID)
            if error == kIOReturnSuccess {
                continuation?.resume()
            } else {
                continuation?.resume(throwing: Failure.channelFailed(psm: psm, error))
            }
        }
    }

    nonisolated public func l2capChannelData(
        _ l2capChannel: IOBluetoothL2CAPChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let message = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        let channelID = ObjectIdentifier(l2capChannel)
        MainActor.assumeIsolated {
            guard channelID == controlChannel.map(ObjectIdentifier.init),
                  let reply = HIDKeyboardProtocol.controlReply(to: message) else { return }
            writeControlReply(reply)
        }
    }

    nonisolated public func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        let channelID = ObjectIdentifier(l2capChannel)
        MainActor.assumeIsolated {
            let ownChannels = [controlChannel, interruptChannel].compactMap { $0.map(ObjectIdentifier.init) }
            guard ownChannels.contains(channelID) else { return }
            disconnect()
            onDisconnect?()
        }
    }
}
