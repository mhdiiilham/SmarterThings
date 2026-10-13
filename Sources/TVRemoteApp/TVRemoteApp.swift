import SwiftUI
import TVRemoteCore

@main
struct TVRemoteApp: App {
    private let model: RemoteViewModel
    private let typing: TypingViewModel
    private let shortcuts: AppShortcutsViewModel

    init() {
        let tokenStore = FileTokenStore(name: "smartthings-token")
        let controller = SmartThingsClient(tokenStore: tokenStore)
        model = RemoteViewModel(controller: controller, tokenStore: tokenStore)

        let hostFinder = TVHostFinder(manualHost: {
            UserDefaults.standard.string(forKey: TypingViewModel.manualHostKey)
        })
        let localTV = LocalTVRemote(
            hostFinder: hostFinder,
            tokenStore: FileTokenStore(name: "local-tv-token")
        )
        typing = TypingViewModel(keyboard: localTV)
        shortcuts = AppShortcutsViewModel(launcher: localTV)
    }

    var body: some Scene {
        MenuBarExtra("TV Remote", systemImage: "tv") {
            RemoteView(model: model, typing: typing, shortcuts: shortcuts)
        }
        .menuBarExtraStyle(.window)
    }
}
