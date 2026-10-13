import Foundation
import Observation
import SmarterThingsCore

@MainActor
@Observable
final class LocalTVPickerViewModel {
    nonisolated static let chosenDeviceIDKey = "localTVDeviceID"
    private static let rememberedDeviceKey = "localTVRememberedDevice"

    private(set) var devices: [LocalTVDevice] = []
    /// The last TV seen on the network, kept so a TV in standby (which doesn't answer
    /// discovery) still has a name and a MAC address to wake it with.
    private(set) var rememberedDevice: LocalTVDevice?
    private(set) var isSearching = false
    private(set) var chosenDeviceID: String?

    private let hostFinder: TVHostFinder
    private let reconnect: @Sendable () async -> Void
    private let defaults: UserDefaults

    /// `reconnect` drops the current connection so the next command goes to the newly chosen TV.
    init(hostFinder: TVHostFinder, defaults: UserDefaults = .standard, reconnect: @escaping @Sendable () async -> Void) {
        self.hostFinder = hostFinder
        self.defaults = defaults
        self.reconnect = reconnect
        chosenDeviceID = defaults.string(forKey: Self.chosenDeviceIDKey)
        rememberedDevice = defaults.data(forKey: Self.rememberedDeviceKey)
            .flatMap { try? JSONDecoder().decode(LocalTVDevice.self, from: $0) }
    }

    /// The TV commands go to: the chosen one if it's on the network, otherwise the first found,
    /// otherwise the last one seen (e.g. it's in standby).
    var activeDevice: LocalTVDevice? {
        devices.first { $0.id == chosenDeviceID } ?? devices.first ?? rememberedDevice
    }

    func searchIfNeeded() async {
        if devices.isEmpty { await search() }
    }

    func search() async {
        guard !isSearching else { return }
        isSearching = true
        devices = await hostFinder.devices()
        isSearching = false
        remember(activeDevice)
    }

    func choose(_ device: LocalTVDevice) {
        guard device.id != chosenDeviceID else { return }
        chosenDeviceID = device.id
        defaults.set(device.id, forKey: Self.chosenDeviceIDKey)
        remember(device)
        Task { await reconnect() }
    }

    private func remember(_ device: LocalTVDevice?) {
        guard let device, device != rememberedDevice else { return }
        rememberedDevice = device
        defaults.set(try? JSONEncoder().encode(device), forKey: Self.rememberedDeviceKey)
    }
}
