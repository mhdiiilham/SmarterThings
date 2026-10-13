// Draws the SmarterThings app icon (a remote with Wi-Fi waves) and renders every
// macOS icon size into an .iconset, which make-icon.sh turns into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit
import SwiftUI

/// macOS icon grid: 1024-point canvas, 824-point tile inset by 100, continuous corners.
private enum Grid {
    static let canvas: CGFloat = 1024
    static let tile: CGFloat = 824
    static let cornerRadius: CGFloat = 185
}

private enum Palette {
    static let tileTop = Color(red: 0.16, green: 0.18, blue: 0.27)
    static let tileBottom = Color(red: 0.05, green: 0.06, blue: 0.10)
    static let lightBlue = Color(red: 0.40, green: 0.75, blue: 1.00)
    static let blue = Color(red: 0.20, green: 0.45, blue: 1.00)
    static let okTop = Color(red: 0.36, green: 0.68, blue: 1.00)
    static let okBottom = Color(red: 0.12, green: 0.42, blue: 0.98)
}

private struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Grid.cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Palette.tileTop, Palette.tileBottom], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: Grid.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            VStack(spacing: 26) {
                Image(systemName: "wifi")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Palette.lightBlue, Palette.blue], startPoint: .top, endPoint: .bottom))
                Remote()
            }
            .offset(y: 30)
        }
        .frame(width: Grid.tile, height: Grid.tile)
        .frame(width: Grid.canvas, height: Grid.canvas)
    }
}

private struct Remote: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 120, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
            .frame(width: 250, height: 460)
            .overlay(alignment: .top) { DirectionPad(size: 190).padding(.top, 44) }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

/// The app's round D-pad: four chevrons around a glowing OK button.
private struct DirectionPad: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.12))
            ForEach(0..<4) { quarter in
                Image(systemName: "chevron.up")
                    .font(.system(size: size * 0.13, weight: .black))
                    .foregroundStyle(.black.opacity(0.45))
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(Double(quarter) * 90))
            }
            Circle()
                .fill(LinearGradient(colors: [Palette.okTop, Palette.okBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: Palette.blue.opacity(0.9), radius: size * 0.06)
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: size * 0.01).frame(width: size * 0.42))
        }
        .frame(width: size, height: size)
    }
}

/// The sizes `iconutil` expects in an .iconset: points × scale.
private let iconSizes: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

@MainActor
private func render(pixels: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: AppIcon().environment(\.colorScheme, .dark))
    renderer.scale = CGFloat(pixels) / Grid.canvas
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

MainActor.assumeIsolated {
    let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for (points, scale) in iconSizes {
        let suffix = scale == 1 ? "" : "@2x"
        try! render(pixels: points * scale, to: iconset.appending(path: "icon_\(points)x\(points)\(suffix).png"))
    }
    print("Rendered \(iconSizes.count) sizes into \(iconset.path)")
}
