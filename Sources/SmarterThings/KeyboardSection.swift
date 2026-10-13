import SwiftUI

/// Connect the Mac as a Bluetooth keyboard and toggle sending key presses to the TV.
struct KeyboardSection: View {
    let model: KeyboardViewModel
    /// The SmartThings TV's name, used to find the same TV among paired Bluetooth devices.
    let tvName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .connected = model.status {
                    Menu {
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
        .task { model.refreshPairedDevices() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .disconnected:
            connectControls
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
            connectControls
        }
    }

    /// One click when the TV is found among paired devices; otherwise a list to choose from.
    @ViewBuilder
    private var connectControls: some View {
        if let device = model.defaultDevice(matching: tvName) {
            HStack(spacing: 6) {
                Button { Task { await model.connect(to: device) } } label: {
                    Label("Connect to \(device.name)", systemImage: "keyboard")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                otherDevicesMenu
            }
        } else {
            otherDevicesMenu
        }
    }

    private var otherDevicesMenu: some View {
        Menu {
            Section("Paired with this Mac") {
                ForEach(model.pairedDevices) { device in
                    Button(device.name) { Task { await model.connect(to: device) } }
                }
            }
            Divider()
            Button("Pair a New Device…") { Task { await model.pairNewDevice() } }
        } label: {
            Label("Choose device", systemImage: "chevron.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which Bluetooth device to type to")
    }
}
