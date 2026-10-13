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
        try write(HIDKeyboardProtocol.inputReport(stroke), on: interruptChannel)
        try write(HIDKeyboardProtocol.inputReport(nil), on: interruptChannel)
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
    private func write(_ bytes: [UInt8], on channel: IOBluetoothL2CAPChannel?) throws {
        guard let channel else { throw Failure.notConnected }
        var buffer = bytes
        let result = buffer.withUnsafeMutableBytes { pointer in
            channel.writeAsync(pointer.baseAddress, length: UInt16(pointer.count), refcon: nil)
        }
        guard result == kIOReturnSuccess else { throw Failure.writeFailed(result) }
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
            try? write(reply, on: controlChannel)
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
