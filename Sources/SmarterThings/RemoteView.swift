import SwiftUI
import SmarterThingsCore

struct RemoteView: View {
    let model: RemoteViewModel
    let typing: TypingViewModel
    let shortcuts: AppShortcutsViewModel
    let localTVs: LocalTVPickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: model.status == .ready ? 724 : 300)
        .task { await model.load() }
        .task { await localTVs.searchIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .needsToken(let reason):
            TokenView(reason: reason) { token in Task { await model.saveToken(token) } }
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            FailureView(message: message) { Task { await model.load() } }
        case .ready:
            remote
        }
    }

    /// Wide layout: navigation | volume & media | shortcuts & typing, so it fits on a laptop screen.
    private var remote: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 0) {
                buttons
                Divider().padding(.horizontal, 18)
                VStack(alignment: .leading, spacing: 16) {
                    if model.canLaunchApps {
                        AppShortcutsSection(model: shortcuts, onLaunch: model.launch)
                    }
                    TypeOnTVField(model: typing, canSearch: model.canSearch)
                }
                .frame(width: 236)
            }
        }
    }

    /// Arrow/Return/Esc shortcuts live here, not on the text field, so typing isn't hijacked.
    private var buttons: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 16) {
                DirectionPad(onPress: model.press)
                    .disabled(!model.supports(.ok))
                HStack(spacing: 14) {
                    LabeledIconButton(symbol: "arrow.uturn.backward", title: "Back") { model.press(.back) }
                    LabeledIconButton(symbol: "house.fill", title: "Home") { model.press(.home) }
                    LabeledIconButton(symbol: "line.3.horizontal", title: "Menu") { model.press(.menu) }
                }
                .disabled(!model.supports(.home))
            }
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Rocker(title: "VOL", upKey: .volumeUp, downKey: .volumeDown, onPress: model.press)
                        .disabled(!model.supports(.volumeUp))
                    LabeledIconButton(
                        symbol: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        title: model.isMuted ? "Unmute" : "Mute",
                        size: 50,
                        action: model.toggleMute
                    )
                    .disabled(!model.supports(.mute))
                    Rocker(title: "CH", upKey: .channelUp, downKey: .channelDown, onPress: model.press)
                        .disabled(!model.supports(.channelUp))
                }
                MediaBar(onPress: model.press)
                    .frame(width: 200)
                    .disabled(!model.supports(.play))
            }
            .padding(.top, 6)
        }
        .fixedSize()
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if model.televisions.count > 1 {
                    Picker("TV", selection: Binding(get: { model.selectedTV }, set: model.select)) {
                        ForEach(model.televisions) { tv in Text(tv.name).tag(Optional(tv)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text(model.selectedTV?.name ?? "TV")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text("SmartThings")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !model.inputSources.isEmpty {
                sourceMenu
            }
            powerButton
        }
    }

    private var sourceMenu: some View {
        Menu {
            Section("Source") {
                ForEach(model.inputSources) { source in
                    Button(source.name) { model.selectInput(source) }
                }
            }
        } label: {
            Text("Source").font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch input (HDMI, TV…)")
    }

    private var powerButton: some View {
        let isOn = model.isPoweredOn == true
        return Button(action: model.togglePower) {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(PressableStyle(
            shape: Circle(),
            fill: isOn ? Color.red : Color.secondary.opacity(0.18),
            pressedFill: isOn ? Color.red.opacity(0.7) : Color.secondary.opacity(0.3),
            foreground: isOn ? Color.white : Color.secondary
        ))
        .animation(.easeOut(duration: 0.15), value: isOn)
        .disabled(!model.supports(.powerOff))
        .help(isOn ? "Turn off" : "Turn on")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.status == .ready {
                FooterButton(symbol: "arrow.clockwise", help: "Refresh TVs") { Task { await model.load() } }
                FooterButton(symbol: "key", help: "Change token") { model.changeToken() }
                LocalTVMenu(model: localTVs)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// Which TV on this network typing and shortcuts talk to. Remembered by the TV's ID, not its IP.
private struct LocalTVMenu: View {
    let model: LocalTVPickerViewModel

    var body: some View {
        Menu {
            Section("TV on this network") {
                if model.isSearching {
                    Text("Searching…")
                } else if model.devices.isEmpty {
                    Text("No Samsung TV found")
                }
                ForEach(model.devices) { device in
                    Button { model.choose(device) } label: {
                        if device == model.activeDevice {
                            Label("\(device.name)  ·  \(device.host)", systemImage: "checkmark")
                        } else {
                            Text("\(device.name)  ·  \(device.host)")
                        }
                    }
                }
            }
            Divider()
            Button("Search Again") { Task { await model.search() } }
        } label: {
            Image(systemName: "wifi")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help(model.activeDevice.map { "Local TV: \($0.name)" } ?? "Choose the TV on this network")
    }
}

private struct FooterButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "tv").font(.system(size: 22)).foregroundStyle(.tint)
            Text("Connect to SmartThings").font(.system(size: 13, weight: .semibold))
            Text(reason ?? "Create a Personal Access Token with device read and execute access, then paste it here.")
                .font(.system(size: 11))
                .foregroundStyle(reason == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Link("Create a token ↗", destination: URL(string: "https://account.smartthings.com/tokens")!)
                .font(.system(size: 11))
            SecureField("Paste token", text: tokenState.projectedValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSave(token) }
            Button { onSave(token) } label: {
                Text("Connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(token.isEmpty)
        }
    }
}

private struct FailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).multilineTextAlignment(.center)
            Button("Try Again", action: onRetry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
