import SwiftUI
import TVRemoteCore

@main
struct TVRemoteApp: App {
    private let model: RemoteViewModel
    private let typing: TypingViewModel

    init() {
        let tokenStore = KeychainTokenStore()
        let controller = SmartThingsClient(tokenStore: tokenStore)
        model = RemoteViewModel(controller: controller, tokenStore: tokenStore)

        let hostFinder = TVHostFinder(manualHost: {
            UserDefaults.standard.string(forKey: TypingViewModel.manualHostKey)
        })
        let keyboard = LocalTVKeyboard(
            hostFinder: hostFinder,
            tokenStore: KeychainTokenStore(account: "local-tv-token")
        )
        typing = TypingViewModel(keyboard: keyboard)
    }

    var body: some Scene {
        MenuBarExtra("TV Remote", systemImage: "tv") {
            RemoteView(model: model, typing: typing)
        }
        .menuBarExtraStyle(.window)
    }
}
