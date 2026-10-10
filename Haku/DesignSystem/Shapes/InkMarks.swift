import SwiftUI

/// Runs a looping clock only when motion is allowed; otherwise renders the static frame (t = nil).
struct MotionClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionDisabled) private var motionDisabled
    @ViewBuilder var content: (Double?) -> Content

    var body: some View {
        if reduceMotion || motionDisabled {
            content(nil)
        } else {
            TimelineView(.animation) { ctx in
                content(ctx.date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

private struct MotionDisabledKey: EnvironmentKey { static let defaultValue = false }
private struct StaticRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Snapshot rendering: ImageRenderer can't draw ScrollView or TextField, so views swap in static stand-ins.
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Forces static frames (previews of the reduced-motion state, snapshot tests).
    var motionDisabled: Bool {
        get { self[MotionDisabledKey.self] }
        set { self[MotionDisabledKey.self] = newValue }
    }
}

/// The squiggle path with its vertical amplitude scaled around the midline by `level`.
struct SquiggleShape: Shape {
    /// 0…1 mic level. 1 reproduces the drawn squiggle exactly.
    var level: CGFloat
    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }
    private static let base = SVGPath.parse(GlyphPaths.squiggle)

    func path(in rect: CGRect) -> Path {
        let mid: CGFloat = 12
        let squash = CGAffineTransform(translationX: 0, y: mid).scaledBy(x: 1, y: max(0.08, level)).translatedBy(x: 0, y: -mid)
        let scale = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 84, y: rect.height / 24)
        return Self.base.applying(squash).applying(scale)
    }
}

/// Listening indicator: ink squiggle driven by the real mic level, redrawn with a stroke trim.
/// Reduced motion: full squiggle at full amplitude, no trim.
struct ListeningSquiggle: View {
    @Environment(\.theme) private var theme
    /// Live mic level 0…1. `nil` shows the static design frame.
    var level: Double?
    var size: CGSize
    var stroke: CGFloat = Strokes.squiggle
    var color: Color?

    var body: some View {
        MotionClock { t in
            let trim = t.map { Motion.writeProgress(time: $0, period: Motion.writePeriod) } ?? 1
            let amp = t == nil ? 1 : CGFloat(0.35 + 0.65 * min(1, max(0, level ?? 1)))
            SquiggleShape(level: amp)
                .trim(from: 0, to: trim)
                .stroke(color ?? theme.colors.ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .animation(.easeOut(duration: 0.08), value: amp)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Blueprint listening: straight-segment zigzag, amplitude follows the mic.
struct ListeningZigzag: View {
    @Environment(\.theme) private var theme
    var level: Double?
    var size: CGSize

    var body: some View {
        MotionClock { t in
            let trim = t.map { Motion.writeProgress(time: $0, period: Motion.writePeriod) } ?? 1
            let amp = t == nil ? 1 : 0.35 + 0.65 * min(1, max(0, level ?? 1))
            SVGShape(GlyphPaths.zigzag, viewBox: CGSize(width: 80, height: 20))
                .trim(from: 0, to: trim)
                .stroke(theme.colors.ink, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                .scaleEffect(x: 1, y: amp)
        }
        .frame(width: size.width, height: size.height * 20 / 24)
        .accessibilityHidden(true)
    }
}

/// Thinking: three ink dots fading in sequence (1.2 s). Static: three solid dots.
struct InkDots: View {
    @Environment(\.theme) private var theme
    var dot: CGFloat = 4
    var body: some View {
        MotionClock { t in
            HStack(spacing: dot) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(theme.colors.ink)
                        .frame(width: dot, height: dot)
                        .opacity(t.map { Motion.dotOpacity(time: $0, index: i) } ?? 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Speaking: hand-drawn underline drawing in on a 2.2 s loop. Static: full underline.
struct HandUnderline: View {
    @Environment(\.theme) private var theme
    var size: CGSize
    var body: some View {
        MotionClock { t in
            SVGShape(GlyphPaths.underline, viewBox: CGSize(width: 70, height: 6))
                .trim(from: 0, to: t.map { Motion.writeProgress(time: $0, period: Motion.underlinePeriod) } ?? 1)
                .stroke(theme.colors.ink, style: StrokeStyle(lineWidth: Strokes.underline, lineCap: .round))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Typewriter listening: block cursor (blinks unless reduced motion).
struct BlockCursor: View {
    @Environment(\.theme) private var theme
    var height: CGFloat
    var body: some View {
        MotionClock { t in
            Rectangle().fill(theme.colors.ink)
                .frame(width: height * 8 / 15, height: height)
                .opacity(t.map { $0.truncatingRemainder(dividingBy: Motion.cursorBlink) < Motion.cursorBlink / 2 ? 1 : 0 } ?? 1)
        }
        .accessibilityHidden(true)
    }
}

/// Job progress in the theme's style: tally strokes, square cells, `[##---]`, or a stamp.
struct ProgressMarks: View {
    @Environment(\.theme) private var theme
    let done: Int
    let total: Int
    var size: CGSize = CGSize(width: 44, height: 16)
    var fontSize: CGFloat = 11
    /// Count shown by the Kraft stamp style (number of running jobs).
    var stampCount: Int = 1

    var body: some View {
        switch theme.progress {
        case .tally:
            HStack(spacing: size.height * 0.375 - Strokes.tally) {
                ForEach(0..<max(total, 0), id: \.self) { i in
                    Capsule().fill(i < done ? (theme.id == .legalPad ? theme.colors.blueInk : theme.colors.ink) : theme.colors.tallyTodo)
                        .frame(width: Strokes.tally, height: size.height * 0.75)
                }
            }
            .frame(height: size.height)
            .accessibilityHidden(true)
        case .squareCells:
            HStack(spacing: 2) {
                ForEach(0..<max(total, 0), id: \.self) { i in
                    if i < done {
                        Rectangle().fill(theme.colors.ink).frame(width: 8, height: 8)
                    } else if i == done {
                        Rectangle().strokeBorder(theme.colors.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])).frame(width: 8, height: 8)
                    } else {
                        Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1).frame(width: 8, height: 8)
                    }
                }
            }
            .accessibilityHidden(true)
        case .bracketHashes:
            let current = done < total ? 1 : 0
            (Text("[" + String(repeating: "#", count: done))
             + Text(current == 1 ? "#" : "").foregroundColor(theme.highlight)
             + Text(String(repeating: "-", count: max(0, total - done - current)) + "]"))
                .font(theme.font(.mono(fontSize)))
                .foregroundStyle(theme.colors.ink)
        case .stamp:
            StampBadge(count: stampCount, color: theme.colors.ink, inline: true)
        }
    }
}

/// Blue-ink ring stamp, rotated −10°, showing how many jobs are running.
struct StampBadge: View {
    @Environment(\.theme) private var theme
    let count: Int
    var color: Color?
    /// Inline (Kraft) uses serif digits and no paper fill.
    var inline = false

    var body: some View {
        let ring = color ?? theme.colors.blueInk
        let shape = AnyShape(theme.chrome.squareCorners ? AnyShape(Rectangle()) : AnyShape(Circle()))
        Text("\(count)")
            .font(inline ? theme.font(.body(13)) : FontFactory.font(theme.type.ui, size: 11, weight: .bold))
            .foregroundStyle(ring)
            .frame(width: WidgetMetrics.stampDiameter, height: WidgetMetrics.stampDiameter)
            .background(inline ? AnyView(Color.clear) : AnyView(shape.fill(theme.colors.paper)))
            .overlay(shape.stroke(ring, lineWidth: Strokes.stamp))
            .rotationEffect(.degrees(WidgetMetrics.stampRotation))
            .accessibilityLabel("\(count) running")
    }
}
