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
        .frame(width: model.status == .ready ? 724 : 320)
        .task { await model.loadIfNeeded() }
        .task { await model.warmUpConnection() }
        .task { await model.watchPowerState() }
    }

    @ViewBuilder
    private var content: some View {
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
                }
            )
        case .ready:
            remote
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
                        TypeOnTVField(model: typing)
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
                HStack(spacing: 14) {
                    LabeledIconButton(symbol: "arrow.uturn.backward", title: "Back") { model.press(.back) }
                    LabeledIconButton(symbol: "house.fill", title: "Home") { model.press(.home) }
                    LabeledIconButton(symbol: "line.3.horizontal", title: "Menu") { model.press(.menu) }
                }
            }
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    Rocker(title: "VOL", upKey: .volumeUp, downKey: .volumeDown, onPress: model.press)
                    LabeledIconButton(
                        symbol: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        title: model.isMuted ? "Unmute" : "Mute",
                        size: 50,
                        action: model.toggleMute
                    )
                    Rocker(title: "CH", upKey: .channelUp, downKey: .channelDown, onPress: model.press)
                }
                MediaBar(onPress: model.press)
                    .frame(width: 200)
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
                Text("Wi-Fi")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            sourceControl
            powerButton
        }
    }

    private var sourceControl: some View {
        Button("Source") { model.press(.source) }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .help("Open the TV's input menu")
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
        .help(isOn ? "Turn off" : "Turn on")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.status == .ready {
                FooterButton(symbol: "arrow.clockwise", help: "Search for the TV again") { Task { await model.searchAgain() } }
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

/// Shown when no TV answers on Wi-Fi.
private struct NoTVFoundView: View {
    let onSearchAgain: () -> Void
    let onSaveAddress: (String) -> Void
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
        }
        .frame(maxWidth: .infinity)
    }
}
