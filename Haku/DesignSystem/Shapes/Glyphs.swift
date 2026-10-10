import SwiftUI

/// Vector paths copied from design/mockups/Margin-Widget-Panel.dc.html.
enum GlyphPaths {
    /// Index card with a tab on the top-left (viewBox 48).
    static let card = "M8 13h11l3-4h18a2 2 0 0 1 2 2v28a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V15a2 2 0 0 1 2-2z"
    /// App-icon card variant (viewBox 48).
    static let iconCard = "M11 15h8l2.5-3H37a1.5 1.5 0 0 1 1.5 1.5v21A1.5 1.5 0 0 1 37 36H11a1.5 1.5 0 0 1-1.5-1.5v-18A1.5 1.5 0 0 1 11 15z"
    /// Listening squiggle (viewBox 84×24).
    static let squiggle = "M2 12 C6 4, 9 20, 13 12 S20 2, 25 12 S32 22, 37 12 S44 5, 49 12 S56 19, 61 12 S68 8, 73 12 S79 15, 82 12"
    /// Blueprint zigzag (viewBox 80×20).
    static let zigzag = "M0 10 L6 4 L12 16 L18 2 L24 18 L30 6 L36 14 L42 3 L48 17 L54 8 L60 12 L66 6 L72 13 L80 10"
    /// Speaking hand-drawn underline (viewBox 70×6).
    static let underline = "M1 4 Q18 1 35 3 T69 2"

    // Icons, viewBox 24, stroke 1.6 round.
    static let tasks = "M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"
    static let settingsLines = "M4 7h9M17 7h3M4 17h3M11 17h9"
    static let collapse = "M5 12h14"
    static let attach = "M20 11.5l-8 8a5 5 0 0 1-7-7l8.5-8.5a3.3 3.3 0 0 1 4.7 4.7L9.7 17a1.7 1.7 0 0 1-2.4-2.4L15 7"
    static let micBody = "M5 11a7 7 0 0 0 14 0M12 18v3"
}

/// The Haku card glyph. Filled ink normally; outlined (stroke 4/48) in error and menu-bar idle.
struct CardGlyph: View {
    enum Style { case filled, outlined }
    var style: Style = .filled
    var color: Color
    /// Draws the highlighter rect across the card (listening state, logo).
    var highlight: Color?
    /// Logo tilt of the highlighter stroke (−3°); the widget uses 0.
    var highlightTilt: Double = 0
    /// Short paper-colored line under the highlighter (logo only).
    var paperLine: Color?

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 48
            ZStack(alignment: .topLeading) {
                switch style {
                case .filled:
                    SVGShape(GlyphPaths.card, viewBox: CGSize(width: 48, height: 48)).fill(color)
                case .outlined:
                    SVGShape(GlyphPaths.card, viewBox: CGSize(width: 48, height: 48))
                        .stroke(color, style: StrokeStyle(lineWidth: Strokes.glyphOutline * s, lineJoin: .round))
                }
                if let highlight {
                    Rectangle().fill(highlight)
                        .frame(width: 24 * s, height: 7 * s)
                        .rotationEffect(.degrees(highlightTilt), anchor: UnitPoint(x: 0.5, y: 3.0 / 7.0))
                        .offset(x: 11 * s, y: 23 * s)
                }
                if let paperLine {
                    RoundedRectangle(cornerRadius: 1 * s).fill(paperLine)
                        .frame(width: 15 * s, height: 2 * s)
                        .offset(x: 12 * s, y: 33 * s)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Stroke icons from the panel header and input row (viewBox 24, 1.6 stroke).
struct InkIcon: View {
    enum Kind { case tasks, settings, collapse, attach, mic }
    let kind: Kind
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 24
            let style = StrokeStyle(lineWidth: lineWidth * s, lineCap: .round, lineJoin: .round)
            let vb = CGSize(width: 24, height: 24)
            ZStack {
                switch kind {
                case .tasks:
                    SVGShape(GlyphPaths.tasks, viewBox: vb).stroke(style: style)
                case .settings:
                    SVGShape(GlyphPaths.settingsLines, viewBox: vb).stroke(style: style)
                    Circle().stroke(style: style).frame(width: 4 * s, height: 4 * s).position(x: 15 * s, y: 7 * s)
                    Circle().stroke(style: style).frame(width: 4 * s, height: 4 * s).position(x: 9 * s, y: 17 * s)
                case .collapse:
                    SVGShape(GlyphPaths.collapse, viewBox: vb).stroke(style: style)
                case .attach:
                    SVGShape(GlyphPaths.attach, viewBox: vb).stroke(style: style)
                case .mic:
                    RoundedRectangle(cornerRadius: 3 * s).stroke(style: style)
                        .frame(width: 6 * s, height: 11 * s).position(x: 12 * s, y: 8.5 * s)
                    SVGShape(GlyphPaths.micBody, viewBox: vb).stroke(style: style)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
