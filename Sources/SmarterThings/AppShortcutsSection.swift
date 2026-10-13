import SwiftUI
import SmarterThingsCore

/// Up to four favorite TV apps; the pencil switches to picking them from the popular-app list.
struct AppShortcutsSection: View {
    let model: AppShortcutsViewModel
    let onLaunch: (TVApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcuts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if model.isEditing { model.finishEditing() } else { Task { await model.startEditing() } }
                } label: {
                    Image(systemName: model.isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(model.isEditing ? "Done" : "Choose favorite apps")
            }

            if model.isEditing { picker } else { tiles }
        }
    }

    private var tiles: some View {
        HStack(spacing: 0) {
            ForEach(0..<AppShortcutsViewModel.maxFavorites, id: \.self) { slot in
                Group {
                    if slot < model.favorites.count {
                        let app = model.favorites[slot]
                        AppTile(app: app) { onLaunch(app) }
                    } else {
                        AddTile { Task { await model.startEditing() } }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        if model.isCheckingTV {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking which apps are on the TV…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            appList
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.isShowingAllKnownApps
                ? "Couldn't reach the TV, so showing all known apps. Pick up to \(AppShortcutsViewModel.maxFavorites)."
                : "Installed on your TV. Pick up to \(AppShortcutsViewModel.maxFavorites).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.availableApps) { app in
                        AppPickerRow(
                            app: app,
                            isFavorite: model.isFavorite(app),
                            isEnabled: model.isFavorite(app) || model.canAddFavorite
                        ) { model.toggleFavorite(app) }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}

private struct AppTile: View {
    let app: TVApp
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AppMonogram(name: app.name, size: 44)
                Text(app.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 56)
            }
        }
        .buttonStyle(PressableStyle(shape: RoundedRectangle(cornerRadius: 10), fill: Color.clear))
        .help("Open \(app.name)")
    }
}

private struct AddTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "plus").font(.system(size: 13, weight: .medium)))
                Text("Add").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressableStyle(shape: RoundedRectangle(cornerRadius: 10), fill: Color.clear))
        .foregroundStyle(.secondary)
        .help("Add a favorite app")
    }
}

private struct AppPickerRow: View {
    let app: TVApp
    let isFavorite: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AppMonogram(name: app.name, size: 22)
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Image(systemName: isFavorite ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isFavorite ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// First letter on a colored tile. Well-known apps get their brand color.
private struct AppMonogram: View {
    let name: String
    let size: CGFloat

    private static let brandColors: [String: Color] = [
        "youtube": .red, "netflix": Color(red: 0.9, green: 0.04, blue: 0.08),
        "prime video": Color(red: 0, green: 0.66, blue: 0.88), "disney+": Color(red: 0.07, green: 0.18, blue: 0.47),
        "spotify": Color(red: 0.11, green: 0.73, blue: 0.33), "apple tv": .black, "twitch": .purple,
    ]
    private static let fallbackColors: [Color] = [.blue, .orange, .teal, .indigo, .pink, .mint, .brown]

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    /// Stable across launches (unlike `hashValue`), so a tile keeps its color.
    private var color: Color {
        if let brand = Self.brandColors[name.lowercased()] { return brand }
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.fallbackColors[seed % Self.fallbackColors.count]
    }
}
