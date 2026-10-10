import SwiftUI

/// `.lnk`: serif, blue ink, 1 pt underline offset 3. Hover → ink.
struct InkLinkStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var size: CGFloat = TypeScale.link
    var color: Color?
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.link(size), theme)
            .foregroundStyle(hovering || configuration.isPressed ? theme.colors.ink : (color ?? theme.colors.blueInk))
            .underline(true, pattern: .solid, color: hovering ? theme.colors.ink : (color ?? theme.colors.blueInk))
            .baselineOffset(0)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// `.ib`: 28 pt square, radius 4, muted icon; hover → ink on paper2.
struct IconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: PanelMetrics.icon, height: PanelMetrics.icon)
            .frame(width: PanelMetrics.iconButton, height: PanelMetrics.iconButton)
            .foregroundStyle(hovering ? theme.colors.ink : theme.colors.muted)
            .background(
                RoundedRectangle(cornerRadius: theme.chrome.squareCorners ? 0 : Radii.iconButton)
                    .fill(hovering || configuration.isPressed ? theme.colors.paper2 : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// `.btn`: sans 700 13, radius 3, 1 pt ink border; `.solid` fills ink; `.warn` uses error.
struct InkButtonStyle: ButtonStyle {
    enum Kind { case outline, solid, warn }
    @Environment(\.theme) private var theme
    var kind: Kind = .outline
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        let tint = kind == .warn ? theme.colors.error : theme.colors.ink
        configuration.label
            .textRole(.button, theme)
            .padding(.horizontal, Spacing.s14)
            .frame(height: height)
            .foregroundStyle(kind == .solid ? theme.colors.paper : tint)
            .background(RoundedRectangle(cornerRadius: theme.chrome.squareCorners ? 0 : Radii.button)
                .fill(kind == .solid ? theme.colors.ink : .clear))
            .overlay(RoundedRectangle(cornerRadius: theme.chrome.squareCorners ? 0 : Radii.button)
                .strokeBorder(tint, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// `.kbd` / `.kc`: mono key cap.
struct KeyCap: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(theme.font(.monoMedium(11.5)))
            .foregroundStyle(theme.colors.ink)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.paper2))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.rule).frame(height: 1).padding(.horizontal, 1)
            }
    }
}

/// `.sc`: small caps label.
struct SmallCaps: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = TypeScale.smallCaps
    var color: Color?
    /// Typewriter shows hints lowercase ("opt+space"); timers keep their case.
    var textCase: Text.Case? = .uppercase
    var body: some View {
        Text(text)
            .font(theme.font(.smallCaps(size)))
            .tracking(theme.tracking(.smallCaps(size)))
            .textCase(textCase)
            .foregroundStyle(color ?? theme.colors.muted)
    }
}
