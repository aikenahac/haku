import SwiftUI

/// Paper fill + texture + border + optional binding strip + CSS-accurate shadow, for any shape.
/// Used by the widget, the panel, windows and confirmation slips.
struct PaperBackground<S: InsettableShape>: View {
    @Environment(\.theme) private var theme
    let shape: S
    var fill: Color?
    var shadow: ShadowStyle?
    var binding: CGFloat = 0
    var textured = false
    var border: Color?
    var dashedTop = false

    var body: some View {
        let shadowStyle = shadow ?? theme.chrome.shadow
        ZStack {
            ForEach(Array(shadowStyle.layers.enumerated()), id: \.offset) { _, layer in
                if !layer.inset {
                    shape
                        .inset(by: -layer.spread)
                        .fill(theme.colors.shadow.opacity(layer.opacity))
                        .offset(x: layer.x, y: layer.y)
                        .blur(radius: layer.blur / 2)
                }
            }
            shape.fill(fill ?? theme.colors.paper)
            if textured {
                TextureView(style: theme.texture).clipShape(shape)
            }
            if binding > 0, let color = theme.colors.binding {
                VStack(spacing: 0) {
                    Rectangle().fill(color).frame(height: binding)
                    Spacer(minLength: 0)
                }
                .clipShape(shape)
            }
            ForEach(Array(shadowStyle.layers.enumerated()), id: \.offset) { _, layer in
                if layer.inset {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(layer.opacity)).frame(height: layer.y)
                        Spacer(minLength: 0)
                    }
                    .clipShape(shape)
                }
            }
            shape.strokeBorder(border ?? theme.colors.border, lineWidth: theme.chrome.borderWidth)
        }
    }
}

extension View {
    /// The standard paper surface for windows and panels (radius 4).
    func paperSurface(radius: CGFloat? = nil, binding: CGFloat = 0, textured: Bool = false) -> some View {
        modifier(PaperSurfaceModifier(radius: radius, binding: binding, textured: textured))
    }
}

private struct PaperSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let radius: CGFloat?
    let binding: CGFloat
    let textured: Bool

    func body(content: Content) -> some View {
        let r = radius ?? theme.chrome.panelRadius
        content
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .background(PaperBackground(shape: RoundedRectangle(cornerRadius: r, style: .continuous),
                                        binding: binding, textured: textured))
    }
}

/// Theme textures: Blueprint grid, Legal pad ruled lines, Kraft speckle.
struct TextureView: View {
    @Environment(\.theme) private var theme
    let style: TextureStyle
    /// Vertical offset so ruled lines can align with text baselines.
    var phase: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            switch style {
            case .none:
                break
            case .grid(let step):
                guard let c = theme.colors.texture else { return }
                var p = Path()
                var x: CGFloat = 0
                while x <= size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += step }
                ctx.fill(p, with: .color(c))
            case .ruled(let step):
                guard let c = theme.colors.texture else { return }
                var p = Path()
                var y = step - 1 + phase
                while y <= size.height { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += step }
                ctx.fill(p, with: .color(c))
            case .speckle:
                // Two dot layers: 7 pt grid dark specks, 11 pt grid light specks offset (3, 5).
                if let dark = theme.colors.texture { dots(&ctx, size, step: 7, offset: .zero, color: dark) }
                if let light = theme.colors.texture2 { dots(&ctx, size, step: 11, offset: CGPoint(x: 3, y: 5), color: light) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dots(_ ctx: inout GraphicsContext, _ size: CGSize, step: CGFloat, offset: CGPoint, color: Color) {
        var p = Path()
        var y = offset.y
        while y < size.height {
            var x = offset.x
            while x < size.width {
                p.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                x += step
            }
            y += step
        }
        ctx.fill(p, with: .color(color))
    }
}

/// Horizontal divider honouring the theme's rule style (dashed in Typewriter).
struct HRule: View {
    @Environment(\.theme) private var theme
    var color: Color?
    var body: some View {
        RuleLine(axis: .horizontal, dashed: theme.ruleStyle == .dashed)
            .stroke(color ?? theme.colors.rule, style: StrokeStyle(lineWidth: 1, dash: theme.ruleStyle == .dashed ? [3, 3] : []))
            .frame(height: 1)
    }
}

/// Vertical divider honouring the theme's rule style.
struct VRule: View {
    @Environment(\.theme) private var theme
    var color: Color?
    var width: CGFloat = 1
    var body: some View {
        RuleLine(axis: .vertical, dashed: theme.ruleStyle == .dashed)
            .stroke(color ?? theme.colors.rule, style: StrokeStyle(lineWidth: width, dash: theme.ruleStyle == .dashed ? [3, 3] : []))
            .frame(width: width)
    }
}

struct RuleLine: Shape {
    let axis: Axis
    let dashed: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if axis == .horizontal {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return p
    }
}
