import SwiftUI
import TVRemoteCore

// MARK: - Direction pad

/// A round D-pad like a physical remote: four ring segments around a raised OK button.
struct DirectionPad: View {
    let onPress: (RemoteKey) -> Void

    private let diameter: CGFloat = 164
    private let okDiameter: CGFloat = 66

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            ForEach(Direction.allCases, id: \.self) { direction in
                Button { onPress(direction.key) } label: {
                    Image(systemName: direction.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .offset(direction.offset(by: (diameter + okDiameter) / 4))
                        .frame(width: diameter, height: diameter)
                }
                .buttonStyle(RingSegmentStyle(direction: direction, innerRatio: okDiameter / diameter))
                .help(direction.help)
            }
            Button { onPress(.ok) } label: {
                Text("OK").font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(width: okDiameter, height: okDiameter)
            }
            .buttonStyle(PressableStyle(shape: Circle(), fill: .tint, pressedFill: .tint, foreground: .white))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .help("OK (Return)")
        }
        .frame(width: diameter, height: diameter)
    }

    enum Direction: CaseIterable {
        case up, right, down, left

        var key: RemoteKey {
            switch self {
            case .up: .up
            case .right: .right
            case .down: .down
            case .left: .left
            }
        }

        var symbol: String { "chevron.\(self)" }
        var help: String { "\(self)".capitalized + " (arrow key)" }

        /// Segments are centered on 0° (up) and go clockwise in 90° steps.
        var centerAngle: Angle { .degrees(Double(Self.allCases.firstIndex(of: self)!) * 90 - 90) }

        func offset(by distance: CGFloat) -> CGSize {
            CGSize(width: cos(centerAngle.radians) * distance, height: sin(centerAngle.radians) * distance)
        }
    }
}

private struct RingSegment: Shape {
    let centerAngle: Angle
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let start = centerAngle - .degrees(45)
        let end = centerAngle + .degrees(45)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct RingSegmentStyle: ButtonStyle {
    let direction: DirectionPad.Direction
    let innerRatio: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let segment = RingSegment(centerAngle: direction.centerAngle, innerRatio: innerRatio)
        configuration.label
            .foregroundStyle(configuration.isPressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(segment.fill(configuration.isPressed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear)))
            .contentShape(segment)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Rocker

/// Vertical +/- pill, like the volume and channel rockers on a remote.
struct Rocker: View {
    let title: String
    let upKey: RemoteKey
    let downKey: RemoteKey
    let onPress: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 0) {
            half(.plus, key: upKey, help: "\(title) up")
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            half(.minus, key: downKey, help: "\(title) down")
        }
        .frame(width: 54, height: 124)
        .background(Capsule().fill(.quaternary))
    }

    private enum Sign: String { case plus, minus }

    private func half(_ sign: Sign, key: RemoteKey, help: String) -> some View {
        Button { onPress(key) } label: {
            Image(systemName: sign.rawValue)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 54, height: 50)
        }
        .buttonStyle(PressableStyle(shape: Capsule(), fill: .clear, pressedFill: .tertiary))
        .help(help)
    }
}

// MARK: - Buttons

/// Round icon button with a caption underneath.
struct LabeledIconButton: View {
    let symbol: String
    let title: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .frame(width: size, height: size)
            }
            .buttonStyle(PressableStyle(shape: Circle(), fill: .quaternary))
            .help(title)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// One capsule holding play/pause/etc. so media keys read as a single group.
struct MediaBar: View {
    let onPress: (RemoteKey) -> Void

    private let keys: [(key: RemoteKey, symbol: String, help: String)] = [
        (.rewind, "backward.fill", "Rewind"),
        (.play, "play.fill", "Play"),
        (.pause, "pause.fill", "Pause"),
        (.stop, "stop.fill", "Stop"),
        (.fastForward, "forward.fill", "Fast forward"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.symbol) { item in
                Button { onPress(item.key) } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(PressableStyle(shape: Capsule(), fill: .clear, pressedFill: .tertiary))
                .help(item.help)
            }
        }
        .padding(3)
        .background(Capsule().fill(.quaternary))
    }
}

/// Shared press feedback: darker fill and a slight shrink while held.
struct PressableStyle<S: Shape>: ButtonStyle {
    private let shape: S
    private let fill: AnyShapeStyle
    private let pressedFill: AnyShapeStyle
    private let foreground: AnyShapeStyle

    init(
        shape: S,
        fill: some ShapeStyle = HierarchicalShapeStyle.quaternary,
        pressedFill: some ShapeStyle = HierarchicalShapeStyle.tertiary,
        foreground: some ShapeStyle = HierarchicalShapeStyle.primary
    ) {
        self.shape = shape
        self.fill = AnyShapeStyle(fill)
        self.pressedFill = AnyShapeStyle(pressedFill)
        self.foreground = AnyShapeStyle(foreground)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(shape.fill(configuration.isPressed ? pressedFill : fill))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
