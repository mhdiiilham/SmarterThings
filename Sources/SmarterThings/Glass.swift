import SwiftUI

extension View {
    /// Liquid Glass in `shape`, optionally tinted; interactive glass reacts to presses.
    func glassSurface(in shape: some Shape, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
    }
}

/// A standalone glass button: interactive glass plus a slight shrink while pressed.
struct GlassSurfaceButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var tint: Color?
    var foreground: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .glassSurface(in: shape, tint: tint, isInteractive: true)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// For parts of a larger glass shape (rocker halves, media keys, app tiles):
/// no glass of their own, just a highlight while pressed.
struct HighlightButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(shape.fill(configuration.isPressed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
