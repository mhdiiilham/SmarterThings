import Foundation
import Observation
import TVRemoteCore

@MainActor
@Observable
final class LocalTVPickerViewModel {
    nonisolated static let chosenDeviceIDKey = "localTVDeviceID"

    private(set) var devices: [LocalTVDevice] = []
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
    }

    /// The TV commands go to: the chosen one if it's on the network, otherwise the first found.
    var activeDevice: LocalTVDevice? {
        devices.first { $0.id == chosenDeviceID } ?? devices.first
    }

    func searchIfNeeded() async {
        if devices.isEmpty { await search() }
    }

    func search() async {
        guard !isSearching else { return }
        isSearching = true
        devices = await hostFinder.devices()
        isSearching = false
    }

    func choose(_ device: LocalTVDevice) {
        guard device.id != chosenDeviceID else { return }
        chosenDeviceID = device.id
        defaults.set(device.id, forKey: Self.chosenDeviceIDKey)
        Task { await reconnect() }
    }
}
