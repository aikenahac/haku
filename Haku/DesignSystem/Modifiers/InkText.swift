import SwiftUI

/// Tags a run of text as highlighted ("marked"). Drawn by `InkTextRenderer`.
struct MarkAttribute: TextAttribute {}

/// Tags a run of text for a red wavy underline (errors, failed status).
struct WavyAttribute: TextAttribute {}

extension Text {
    /// Marks this text with the theme's marking style (highlighter band, fill, dashed box or ribbon red).
    /// The containing view needs `.inkText(theme)` for the mark to draw.
    func marked(_ theme: Theme) -> Text {
        let tagged = customAttribute(MarkAttribute())
        switch theme.marking {
        case .fill: return tagged.foregroundColor(theme.colors.markInk)
        case .ribbonText: return tagged.foregroundColor(theme.highlight)
        case .band, .dashedBox: return tagged
        }
    }

    /// Error text with a wavy underline in the error color.
    func wavy(_ theme: Theme) -> Text {
        customAttribute(WavyAttribute()).foregroundColor(theme.colors.ink)
    }
}

/// Draws highlighter marks and wavy underlines behind/below tagged runs, following the
/// HANDOFF highlighter rule: light = band over 52–92% of the line, dark = full fill.
struct InkTextRenderer: TextRenderer {
    var marking: MarkingStyle
    var markColor: Color
    var boxColor: Color
    var errorColor: Color
    /// Horizontal bleed of the mark (CSS `padding: 0 2px`).
    var markBleed: CGFloat = 2

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let rect = run.typographicBounds.rect
                if run[MarkAttribute.self] != nil {
                    drawMark(rect.insetBy(dx: -markBleed, dy: 0), in: &ctx)
                }
                ctx.draw(run)
                if run[WavyAttribute.self] != nil {
                    drawWavy(under: rect, descent: run.typographicBounds.descent, in: &ctx)
                }
            }
        }
    }

    private func drawMark(_ r: CGRect, in ctx: inout GraphicsContext) {
        switch marking {
        case .band(let top, let bottom):
            let band = CGRect(x: r.minX, y: r.minY + r.height * top, width: r.width, height: r.height * (bottom - top))
            ctx.fill(Path(band), with: .color(markColor))
        case .fill:
            ctx.fill(Path(roundedRect: r, cornerRadius: Radii.mark), with: .color(markColor))
        case .dashedBox:
            let box = r.insetBy(dx: -3, dy: -1)
            ctx.stroke(Path(box), with: .color(boxColor), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .ribbonText:
            break
        }
    }

    private func drawWavy(under r: CGRect, descent: CGFloat, in ctx: inout GraphicsContext) {
        let y = r.maxY - descent + TypeScale.wavyOffset
        ctx.stroke(WavyLine.path(from: r.minX, to: r.maxX, y: y), with: .color(errorColor),
                   style: StrokeStyle(lineWidth: Strokes.wavy, lineCap: .round, lineJoin: .round))
    }
}

enum WavyLine {
    /// A wavy underline like CSS `text-decoration: underline wavy` (period ~6 pt, amplitude ~1.5 pt).
    static func path(from x0: CGFloat, to x1: CGFloat, y: CGFloat, period: CGFloat = 6, amplitude: CGFloat = 1.5) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y))
        var x = x0
        var up = true
        while x < x1 {
            let next = min(x + period / 2, x1)
            p.addQuadCurve(to: CGPoint(x: next, y: y), control: CGPoint(x: (x + next) / 2, y: y + (up ? -amplitude * 2 : amplitude * 2)))
            x = next
            up.toggle()
        }
        return p
    }
}

extension View {
    /// Installs the ink renderer so `.marked()` / `.wavy()` runs draw.
    func inkText(_ theme: Theme) -> some View {
        textRenderer(InkTextRenderer(marking: theme.marking, markColor: theme.highlight,
                                     boxColor: theme.colors.ink, errorColor: theme.colors.error))
    }

    /// Applies a text role's font, tracking and case from the theme.
    func textRole(_ role: TextRole, _ theme: Theme) -> some View {
        font(theme.font(role))
            .tracking(theme.tracking(role))
            .textCase(theme.textCase(role))
    }

    /// Line height as a multiple of the font size (CSS `line-height`).
    func lineHeight(_ multiple: CGFloat, size: CGFloat) -> some View {
        lineSpacing(max(0, (multiple - 1.2) * size))
    }
}
