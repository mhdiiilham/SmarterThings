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
        // The most-pressed keys go over the local network: SmartThings allows only
        // 12 commands a minute per TV. Everything else stays on the cloud.
        let keyDispatcher = KeyDispatcher(
            local: localTV,
            cloud: controller,
            localKeys: [.up, .down, .left, .right, .ok, .volumeUp, .volumeDown]
        )
        model = RemoteViewModel(controller: controller, keyDispatcher: keyDispatcher, tokenStore: tokenStore)
        typing = TypingViewModel(keyboard: localTV) { [model] query in try await model.search(query) }
        shortcuts = AppShortcutsViewModel(
            knownApps: PopularApps.all,
            installedAppFinder: LocalInstalledApps(hostFinder: hostFinder)
        )
        localTVs = LocalTVPickerViewModel(hostFinder: hostFinder) {
            await hostFinder.forgetDiscoveredHost()
            await localTV.disconnect()
        }

        // Search at launch, not when the popover opens: the first search triggers macOS's
        // "Allow local network" prompt, which takes focus and would close the popover.
        let localTVs = localTVs
        Task { await localTVs.searchIfNeeded() }
    }

    var body: some Scene {
        MenuBarExtra("SmarterThings", systemImage: "tv") {
            RemoteView(model: model, typing: typing, shortcuts: shortcuts, localTVs: localTVs, keyboard: keyboard)
        }
        .menuBarExtraStyle(.window)
    }
}
