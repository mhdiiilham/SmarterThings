import SwiftUI

/// Connect the Mac as a Bluetooth keyboard and toggle sending key presses to the TV.
struct KeyboardSection: View {
    let model: KeyboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .connected = model.status {
                    Menu {
                        Button("Switch TV…") { Task { await model.chooseTVAndConnect() } }
                        Button("Disconnect") { model.disconnect() }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                }
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .disconnected:
            Button { Task { await model.connect() } } label: {
                Label("Connect as Bluetooth keyboard", systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting… accept on the TV if asked.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .connected(let tvName):
            Button(action: model.toggleTyping) {
                Label(model.isTyping ? "Typing to \(tvName)" : "Start typing to TV",
                      systemImage: model.isTyping ? "keyboard.fill" : "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(model.isTyping ? .green : .accentColor)
            Text(model.isTyping
                ? "Your Mac's keys now go to the TV while this menu is open. Click again to stop."
                : "Works in YouTube, Netflix and any other app.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { Task { await model.connect() } }
                .controlSize(.small)
        }
    }
}
