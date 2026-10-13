import SwiftUI
import SmarterThingsCore

struct RemoteView: View {
    let model: RemoteViewModel
    let typing: TypingViewModel
    let shortcuts: AppShortcutsViewModel
    let localTVs: LocalTVPickerViewModel
    let keyboard: KeyboardViewModel

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
        .frame(width: model.status == .ready && !model.isEditingToken ? 724 : 320)
        .task { await model.loadIfNeeded() }
        .task { await model.warmUpLocalKeys() }
        .task { await model.watchPowerState() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEditingToken {
            TokenView(
                hasToken: model.hasToken,
                onSave: { token in Task { await model.saveToken(token) } },
                onRemove: model.removeToken,
                onCancel: { model.isEditingToken = false }
            )
        } else {
            switch model.status {
            case .searching:
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your TV on Wi-Fi…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            case .noTVFound:
                NoTVFoundView(
                    onSearchAgain: { Task { await model.searchAgain() } },
                    onSaveAddress: { address in
                        typing.saveManualHost(address)
                        Task { await model.searchAgain() }
                    },
                    onConnectSmartThings: { model.isEditingToken = true }
                )
            case .ready:
                remote
            }
        }
    }

    /// Wide layout: navigation | volume & media | shortcuts & typing, so it fits on a laptop screen.
    private var remote: some View {
        VStack(spacing: 16) {
            header
                .overlay(alignment: .center) { noticeBanner }
                .animation(.easeOut(duration: 0.2), value: model.notice)
            HStack(alignment: .top, spacing: 0) {
                GlassEffectContainer { buttons }
                Divider().padding(.horizontal, 18)
                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.canLaunchApps {
                            AppShortcutsSection(model: shortcuts, onLaunch: model.launch)
                        }
                        KeyboardSection(model: keyboard, tvName: model.tvName)
                        TypeOnTVField(model: typing, canSearch: model.canSearch)
                    }
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

    /// Floats over the header so a failed command doesn't shift the layout.
    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassSurface(in: Capsule())
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.tvName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.connectionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            sourceControl
            powerButton
        }
    }

    /// Named inputs need SmartThings; without it, Source opens the TV's own input menu.
    @ViewBuilder
    private var sourceControl: some View {
        if model.inputSources.isEmpty {
            Button("Source") { model.press(.source) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .help("Open the TV's input menu")
        } else {
            Menu {
                Section("Source") {
                    ForEach(model.inputSources) { source in
                        Button(source.name) { model.selectInput(source) }
                    }
                }
                Divider()
                Button("Open Input Menu on TV") { model.press(.source) }
            } label: {
                Text("Source").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch input (HDMI, TV…)")
        }
    }

    private var powerButton: some View {
        let isOn = model.isPoweredOn == true
        return Button(action: model.togglePower) {
            Group {
                if model.isChangingPower {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "power").font(.system(size: 12, weight: .bold))
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(GlassSurfaceButtonStyle(
            shape: Circle(),
            tint: isOn ? .red : nil,
            foreground: isOn ? .white : .secondary
        ))
        .animation(.easeOut(duration: 0.15), value: isOn)
        .disabled(!model.supports(.powerOff))
        .help(isOn ? "Turn off" : "Turn on")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.status == .ready {
                FooterButton(symbol: "arrow.clockwise", help: "Search for the TV again") { Task { await model.searchAgain() } }
                FooterButton(symbol: "key", help: "SmartThings (optional)") { model.isEditingToken = true }
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

/// SmartThings is optional: it adds TV search, named inputs and use away from home.
private struct TokenView: View {
    let hasToken: Bool
    let onSave: (String) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void
    // `@State` is a macro in this SDK and its plugin only ships with Xcode; the plain
    // State type still works because SwiftUI finds DynamicProperty fields itself.
    private let tokenState = State(initialValue: "")
    private var token: String { tokenState.wrappedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SmartThings (optional)").font(.system(size: 13, weight: .semibold))
            Text("The remote works over Wi-Fi without this. A token adds TV search, named input sources and control away from home. Tokens expire after 24 hours.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Create a token ↗", destination: URL(string: "https://account.smartthings.com/tokens")!)
                .font(.system(size: 11))
            SecureField(hasToken ? "Paste a new token" : "Paste token", text: tokenState.projectedValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSave(token) }
            HStack {
                Button("Cancel", action: onCancel)
                if hasToken {
                    Button("Remove Token", role: .destructive, action: onRemove)
                }
                Spacer()
                Button("Save") { onSave(token) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.isEmpty)
            }
            .controlSize(.small)
        }
    }
}

/// Shown when no TV answers on Wi-Fi and there's no SmartThings TV either.
private struct NoTVFoundView: View {
    let onSearchAgain: () -> Void
    let onSaveAddress: (String) -> Void
    let onConnectSmartThings: () -> Void
    private let addressState = State(initialValue: "")

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv.slash").font(.title2).foregroundStyle(.secondary)
            Text("No TV found on this Wi-Fi").font(.system(size: 13, weight: .semibold))
            Text("Make sure the TV is on and on the same network, and that SmarterThings is allowed in System Settings › Privacy & Security › Local Network.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Search Again", action: onSearchAgain).buttonStyle(.glass)
            HStack(spacing: 6) {
                TextField("Or enter the TV's IP address", text: addressState.projectedValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onSaveAddress(addressState.wrappedValue) }
                Button("Use") { onSaveAddress(addressState.wrappedValue) }
                    .disabled(addressState.wrappedValue.isEmpty)
            }
            .controlSize(.small)
            Button("Connect SmartThings instead…", action: onConnectSmartThings)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity)
    }
}
