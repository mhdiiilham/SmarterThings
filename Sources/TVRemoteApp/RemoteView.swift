import SwiftUI
import TVRemoteCore

struct RemoteView: View {
    @Bindable var model: RemoteViewModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.status {
            case .needsToken(let reason):
                TokenView(reason: reason) { token in Task { await model.saveToken(token) } }
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let message):
                FailureView(message: message) { Task { await model.load() } }
            case .ready:
                remote
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 260)
        .task { await model.load() }
    }

    private var remote: some View {
        VStack(spacing: 14) {
            header
            DirectionPad(model: model)
            HStack(alignment: .top, spacing: 16) {
                Rocker(title: "VOL", up: .volumeUp, down: .volumeDown, model: model)
                VStack(spacing: 8) {
                    KeyButton(
                        symbol: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        help: "Mute"
                    ) { model.toggleMute() }
                        .disabled(!model.supports(.mute))
                    KeyButton(symbol: "house.fill", help: "Home") { model.press(.home) }
                        .disabled(!model.supports(.home))
                    KeyButton(symbol: "line.3.horizontal", help: "Menu") { model.press(.menu) }
                        .disabled(!model.supports(.menu))
                }
                Rocker(title: "CH", up: .channelUp, down: .channelDown, model: model)
            }
            MediaRow(model: model)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.press(.up); return .handled }
        .onKeyPress(.downArrow) { model.press(.down); return .handled }
        .onKeyPress(.leftArrow) { model.press(.left); return .handled }
        .onKeyPress(.rightArrow) { model.press(.right); return .handled }
        .onKeyPress(.return) { model.press(.ok); return .handled }
        .onKeyPress(.escape) { model.press(.back); return .handled }
    }

    private var header: some View {
        HStack {
            if model.televisions.count > 1 {
                Picker("TV", selection: $model.selectedTV) {
                    ForEach(model.televisions) { tv in Text(tv.name).tag(Optional(tv)) }
                }
                .labelsHidden()
            } else {
                Text(model.selectedTV?.name ?? "TV").font(.headline).lineLimit(1)
            }
            Spacer()
            if !model.inputSources.isEmpty {
                Menu {
                    ForEach(model.inputSources) { source in
                        Button(source.name) { model.selectInput(source) }
                    }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Source")
            }
            Menu {
                Button("Turn On") { model.press(.powerOn) }
                Button("Turn Off") { model.press(.powerOff) }
            } label: {
                Image(systemName: "power")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!model.supports(.powerOff))
            .help("Power")
        }
    }

    private var footer: some View {
        HStack {
            if model.status == .ready {
                Button("Refresh") { Task { await model.load() } }
                Button("Token…") { model.changeToken() }
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct DirectionPad: View {
    let model: RemoteViewModel

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                KeyButton(symbol: "arrow.uturn.backward", help: "Back") { model.press(.back) }
                pad(.up, "chevron.up")
                Color.clear.frame(width: 36, height: 36)
            }
            GridRow {
                pad(.left, "chevron.left")
                KeyButton(title: "OK", help: "OK", isProminent: true) { model.press(.ok) }
                pad(.right, "chevron.right")
            }
            GridRow {
                Color.clear.frame(width: 36, height: 36)
                pad(.down, "chevron.down")
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .disabled(!model.supports(.ok))
    }

    private func pad(_ key: RemoteKey, _ symbol: String) -> some View {
        KeyButton(symbol: symbol, help: "\(key)".capitalized) { model.press(key) }
    }
}

private struct Rocker: View {
    let title: String
    let up: RemoteKey
    let down: RemoteKey
    let model: RemoteViewModel

    var body: some View {
        VStack(spacing: 4) {
            KeyButton(symbol: "plus", help: "\(title) up") { model.press(up) }
            Text(title).font(.caption2).foregroundStyle(.secondary)
            KeyButton(symbol: "minus", help: "\(title) down") { model.press(down) }
        }
        .disabled(!model.supports(up))
    }
}

private struct MediaRow: View {
    let model: RemoteViewModel

    private let keys: [(RemoteKey, String)] = [
        (.rewind, "backward.fill"), (.play, "play.fill"), (.pause, "pause.fill"),
        (.stop, "stop.fill"), (.fastForward, "forward.fill"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.1) { key, symbol in
                KeyButton(symbol: symbol, help: "\(key)".capitalized) { model.press(key) }
            }
        }
        .disabled(!model.supports(.play))
    }
}

private struct KeyButton: View {
    var symbol: String?
    var title: String?
    let help: String
    var isProminent = false
    let action: () -> Void

    init(symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    init(title: String, help: String, isProminent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.isProminent = isProminent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "").bold() }
            }
            .frame(width: 36, height: 36)
            .background(isProminent ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct TokenView: View {
    let reason: String?
    let onSave: (String) -> Void
    // `@State` is a macro in this SDK and its plugin only ships with Xcode; the plain
    // State type still works because SwiftUI finds DynamicProperty fields itself.
    private let tokenState = State(initialValue: "")
    private var token: String { tokenState.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SmartThings token").font(.headline)
            Text(reason ?? "Create a Personal Access Token with device read and execute scopes, then paste it here.")
                .font(.caption)
                .foregroundStyle(reason == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Link("Open account.smartthings.com/tokens",
                 destination: URL(string: "https://account.smartthings.com/tokens")!)
                .font(.caption)
            SecureField("Token", text: tokenState.projectedValue)
                .onSubmit { onSave(token) }
            Button("Save") { onSave(token) }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty)
        }
    }
}

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text(message).font(.callout).multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
