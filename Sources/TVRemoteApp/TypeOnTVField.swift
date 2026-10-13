import SwiftUI

/// Sends text to the TV: Return types into the open Samsung keyboard (local network),
/// the magnifier runs the TV's own search (SmartThings cloud).
struct TypeOnTVField: View {
    let model: TypingViewModel
    let canSearch: Bool
    // `@State` is a macro whose plugin only ships with Xcode; see TokenView.
    private let textState = State(initialValue: "")
    private let addressState = State(initialValue: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Type or search on TV…", text: textState.projectedValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(send)
                if canSearch {
                    Button(action: search) {
                        Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 17))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(isBusyOrEmpty)
                    .help("Search on TV")
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .disabled(isBusyOrEmpty)
                .help("Type into the TV's open keyboard (Return)")
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
            caption(canSearch
                ? "Return types into the TV's open keyboard. 🔍 runs a TV search."
                : "Open a search box on the TV, then type here.", style: .secondary)
        case .sending:
            caption("Sending… The first time, choose Allow on the TV.", style: .secondary)
        case .sent:
            caption("Sent to TV. YouTube ignores this; use 🔍 there.", style: .green)
        case .searched:
            caption("Search sent to TV.", style: .green)
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

    private var isBusyOrEmpty: Bool {
        textState.wrappedValue.isEmpty || model.status == .sending
    }

    private func search() {
        let query = textState.wrappedValue
        Task {
            await model.search(query)
            if model.status == .searched { textState.wrappedValue = "" }
        }
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
