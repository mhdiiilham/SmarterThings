import SwiftUI
import TVRemoteCore

@main
struct TVRemoteApp: App {
    private let model: RemoteViewModel

    init() {
        let tokenStore = KeychainTokenStore()
        let controller = SmartThingsClient(tokenStore: tokenStore)
        model = RemoteViewModel(controller: controller, tokenStore: tokenStore)
    }

    var body: some Scene {
        MenuBarExtra("TV Remote", systemImage: "tv") {
            RemoteView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
