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

    nonisolated static let tvAddressKey = "bluetoothKeyboardTVAddress"

    private(set) var status: Status = .disconnected
    private(set) var isTyping = false

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

    /// Reconnects to the remembered TV, or asks which TV to use the first time.
    func connect() async {
        status = .connecting
        if let address = defaults.string(forKey: Self.tvAddressKey),
           (try? await keyboard.connect(toAddress: address)) != nil {
            markConnected()
            return
        }
        await chooseTVAndConnect()
    }

    /// Shows macOS's Bluetooth device picker, e.g. to switch TVs.
    func chooseTVAndConnect() async {
        status = .connecting
        guard let selector = IOBluetoothDeviceSelectorController.deviceSelector() else {
            status = .failed("Bluetooth isn't available on this Mac.")
            return
        }
        selector.setTitle("SmarterThings Keyboard")
        selector.setPrompt("Connect")
        selector.setDescriptionText("Choose your TV. The first time, accept the pairing code on the TV.")
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
        case BluetoothHIDKeyboard.Failure.connectionFailed:
            "Couldn't connect. Make sure the TV is on and KeyPad (or another keyboard app) isn't connected."
        case BluetoothHIDKeyboard.Failure.channelFailed:
            "The TV didn't accept the keyboard. Remove the Mac from the TV's Bluetooth devices and try again."
        case BluetoothHIDKeyboard.Failure.bluetoothUnavailable:
            "Couldn't set up Bluetooth. Is Bluetooth on, and allowed for SmarterThings?"
        default:
            error.localizedDescription
        }
    }
}
