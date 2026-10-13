import AppKit
import IOBluetooth
import IOBluetoothUI
import Observation
import SmarterThingsCore

/// The Mac's physical keyboard as a Bluetooth keyboard for the TV. While typing is on,
/// key presses in SmarterThings go to the TV instead of the app.
@MainActor
@Observable
final class KeyboardViewModel {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(tvName: String)
        case failed(String)
    }

    /// A Bluetooth device this Mac is already paired with.
    struct PairedDevice: Identifiable, Hashable {
        let id: String   // Bluetooth address
        let name: String
    }

    nonisolated static let tvAddressKey = "bluetoothKeyboardTVAddress"

    private(set) var status: Status = .disconnected
    private(set) var isTyping = false
    private(set) var pairedDevices: [PairedDevice] = []

    private let keyboard: BluetoothHIDKeyboard
    private let defaults: UserDefaults
    private var keyMonitor: Any?

    init(keyboard: BluetoothHIDKeyboard, defaults: UserDefaults = .standard) {
        self.keyboard = keyboard
        self.defaults = defaults
        keyboard.onDisconnect = { [weak self] in
            self?.stopTyping()
            self?.status = .disconnected
        }
    }

    /// Already-paired devices, refreshed when the connect menu opens.
    func refreshPairedDevices() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedDevices = devices
            .map { PairedDevice(id: $0.addressString, name: $0.name ?? $0.addressString) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// The remembered TV, else the paired device named like the SmartThings TV.
    func defaultDevice(matching tvName: String?) -> PairedDevice? {
        let remembered = defaults.string(forKey: Self.tvAddressKey)
        return pairedDevices.first { $0.id == remembered }
            ?? pairedDevices.first { $0.name == tvName }
    }

    func connect(to device: PairedDevice) async {
        status = .connecting
        do {
            try await keyboard.connect(toAddress: device.id)
            defaults.set(device.id, forKey: Self.tvAddressKey)
            markConnected()
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    /// macOS's Bluetooth picker. It only lists discoverable devices, so it's for pairing a new TV;
    /// an already-paired TV appears in `pairedDevices` instead.
    func pairNewDevice() async {
        status = .connecting
        guard let selector = IOBluetoothDeviceSelectorController.deviceSelector() else {
            status = .failed("Bluetooth isn't available on this Mac.")
            return
        }
        selector.setTitle("SmarterThings Keyboard")
        selector.setPrompt("Connect")
        selector.setDescriptionText("Make the TV discoverable (TV: Settings › Connection › Bluetooth Device List), then choose it and accept the pairing code.")
        NSApp.activate()
        guard selector.runModal() == Int32(kIOBluetoothUISuccess),
              let device = selector.getResults()?.first as? IOBluetoothDevice else {
            status = .disconnected
            return
        }
        do {
            try await keyboard.connect(to: device)
            defaults.set(device.addressString, forKey: Self.tvAddressKey)
            markConnected()
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    func disconnect() {
        stopTyping()
        keyboard.disconnect()
        status = .disconnected
        refreshPairedDevices()
    }

    func toggleTyping() {
        if isTyping { stopTyping() } else { startTyping() }
    }

    private func startTyping() {
        guard keyboard.isConnected, keyMonitor == nil else { return }
        isTyping = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let stroke = Self.stroke(for: event) else { return event }
            Task { try? await self.keyboard.send(stroke) }
            return nil
        }
    }

    private func stopTyping() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isTyping = false
    }

    private func markConnected() {
        status = .connected(tvName: keyboard.connectedDeviceName ?? "TV")
    }

    private static func stroke(for event: NSEvent) -> HIDKeyStroke? {
        var modifiers: HIDModifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        // Command shortcuts stay with the Mac.
        guard !event.modifierFlags.contains(.command) else { return nil }
        return MacKeyCodeMap.stroke(forKeyCode: event.keyCode, modifiers: modifiers)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case BluetoothHIDKeyboard.Failure.connectionFailed(let code):
            "Couldn't connect (\(hex(code))). Make sure the TV is on and KeyPad (or another keyboard app) isn't connected."
        case BluetoothHIDKeyboard.Failure.channelFailed(let psm, let code):
            "The TV didn't accept the keyboard (channel 0x\(String(psm, radix: 16)), \(hex(code))). Try again; if it keeps failing, remove the Mac from the TV's Bluetooth devices."
        case BluetoothHIDKeyboard.Failure.bluetoothUnavailable:
            "Couldn't set up Bluetooth. Is Bluetooth on, and allowed for SmarterThings?"
        default:
            error.localizedDescription
        }
    }

    private static func hex(_ code: IOReturn) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16)
    }
}
