import SwiftUI

/// Text field that sends what you type to the TV's on-screen keyboard (e.g. YouTube search).
struct TypeOnTVField: View {
    let model: TypingViewModel
    // `@State` is a macro whose plugin only ships with Xcode; see TokenView.
    private let textState = State(initialValue: "")
    private let addressState = State(initialValue: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Type on TV…", text: textState.projectedValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .disabled(textState.wrappedValue.isEmpty || model.status == .sending)
                .help("Send to TV (Return)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 32)
            .background(Capsule().fill(.quaternary))

            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .idle:
            caption("Open a search box on the TV, then type here.", style: .secondary)
        case .sending:
            caption("Sending… The first time, choose Allow on the TV.", style: .secondary)
        case .sent:
            caption("Sent to TV.", style: .green)
        case .failed(let message, let canEnterAddress):
            caption(message, style: .orange)
            if canEnterAddress { addressField }
        }
    }

    private var addressField: some View {
        HStack(spacing: 6) {
            TextField(model.manualHost.isEmpty ? "TV IP, e.g. 192.168.1.20" : model.manualHost,
                      text: addressState.projectedValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit(saveAddress)
            Button("Save", action: saveAddress)
                .controlSize(.small)
                .disabled(addressState.wrappedValue.isEmpty)
        }
    }

    private func caption(_ text: String, style: some ShapeStyle) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func send() {
        let text = textState.wrappedValue
        Task {
            await model.type(text)
            if model.status == .sent { textState.wrappedValue = "" }
        }
    }

    private func saveAddress() {
        model.saveManualHost(addressState.wrappedValue)
        addressState.wrappedValue = ""
    }
}
