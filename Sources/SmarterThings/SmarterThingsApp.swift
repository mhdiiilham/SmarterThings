import SwiftUI
import SmarterThingsCore

@main
struct SmarterThingsApp: App {
    private let model: RemoteViewModel
    private let typing: TypingViewModel
    private let shortcuts: AppShortcutsViewModel
    private let localTVs: LocalTVPickerViewModel
    private let keyboard = KeyboardViewModel(keyboard: BluetoothHIDKeyboard())

    init() {
        let tokenStore = FileTokenStore(name: "smartthings-token")
        let controller = SmartThingsClient(tokenStore: tokenStore)

        let hostFinder = TVHostFinder(
            manualHost: { UserDefaults.standard.string(forKey: TypingViewModel.manualHostKey) },
            chosenDeviceID: { UserDefaults.standard.string(forKey: LocalTVPickerViewModel.chosenDeviceIDKey) }
        )
        let localTV = LocalTVRemote(
            hostFinder: hostFinder,
            tokenStore: FileTokenStore(name: "local-tv-token")
        )
        let localTVs = LocalTVPickerViewModel(hostFinder: hostFinder) {
            await hostFinder.forgetDiscoveredHost()
            await localTV.disconnect()
        }
        self.localTVs = localTVs
        let localApps = LocalInstalledApps(hostFinder: hostFinder)

        // Every key goes over Wi-Fi (no token, no rate limit); SmartThings is only a fallback.
        let keyDispatcher = KeyDispatcher(
            local: localTV,
            cloud: controller,
            localKeys: Set(RemoteKey.allCases).subtracting([.powerOn])
        )
        let power = PowerControl(
            keys: keyDispatcher,
            cloud: controller,
            localPowerState: {
                guard let host = try? await hostFinder.host() else { return nil }
                return await LocalTVDiscovery.isPoweredOn(host: host)
            },
            wake: {
                guard let mac = await localTVs.activeDevice?.macAddress else {
                    throw WakeOnLAN.Failure.invalidMACAddress
                }
                try await WakeOnLAN.wake(macAddress: mac)
            }
        )
        model = RemoteViewModel(
            localTVs: localTVs,
            controller: controller,
            keyDispatcher: keyDispatcher,
            appLauncher: AppLauncher(local: localApps, cloud: controller),
            power: power,
            tokenStore: tokenStore
        )
        typing = TypingViewModel(keyboard: localTV) { [model] query in try await model.search(query) }
        shortcuts = AppShortcutsViewModel(knownApps: PopularApps.all, installedAppFinder: localApps)

        // Search at launch, not when the popover opens: the first search triggers macOS's
        // "Allow local network" prompt, which takes focus and would close the popover.
        Task { await localTVs.searchIfNeeded() }
    }

    var body: some Scene {
        MenuBarExtra("SmarterThings", systemImage: "tv") {
            RemoteView(model: model, typing: typing, shortcuts: shortcuts, localTVs: localTVs, keyboard: keyboard)
        }
        .menuBarExtraStyle(.window)
    }
}
