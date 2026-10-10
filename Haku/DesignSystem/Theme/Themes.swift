import SwiftUI

extension Theme {
    /// Resolves a theme for an appearance. `scheme` only matters for Daylight/Carbon;
    /// extra themes use their fixed appearance.
    static func resolve(_ id: ThemeID,
                        scheme requested: ColorScheme? = nil,
                        highlighter: HighlighterColor = .yellow,
                        density: DensityMetrics = .comfortable) -> Theme {
        switch id {
        case .daylight, .carbon:
            let scheme = requested ?? (id == .carbon ? .dark : .light)
            return margin(scheme: scheme, highlighter: highlighter, density: density)
        case .blueprint: return blueprint(density: density)
        case .legalPad: return legalPad(density: density)
        case .typewriter: return typewriter(density: density)
        case .kraft: return kraft(density: density)
        }
    }

    private static let marginType = ThemeTypography(
        voice: .newsreader, ui: .atkinson, code: .plexMono, chrome: .newsreader,
        chromeItalic: true, chromeCase: .none, chromeTracking: 0, stateScale: 1,
        userLine: .newsreader, userLineItalic: true)

    /// Margin — paper & ink. Light = Daylight, dark = Carbon.
    static func margin(scheme: ColorScheme, highlighter: HighlighterColor, density: DensityMetrics) -> Theme {
        let dark = scheme == .dark
        return Theme(
            id: dark ? .carbon : .daylight,
            scheme: scheme,
            colors: .named("Margin"),
            highlight: highlighter.color,
            type: marginType,
            marking: dark ? .fill : .band(top: 0.52, bottom: 0.92),
            texture: .none,
            ruleStyle: .solid,
            marginRule: .single,
            progress: .tally,
            listening: .squiggle(stroke: Strokes.squiggle, useBlueInk: false),
            chrome: ThemeChrome(widgetRadius: Radii.widget, panelRadius: Radii.panel, borderWidth: 1,
                                shadow: dark ? .paperDark : .paperLight),
            copy: ThemeCopy(),
            density: density)
    }

    /// Blueprint — IBM Plex Mono uppercase, square corners, 16 pt grid, dashed-box marking.
    static func blueprint(density: DensityMetrics) -> Theme {
        let colors = ThemeColors.named("Blueprint")
        return Theme(
            id: .blueprint, scheme: .dark, colors: colors,
            highlight: colors.highlight ?? colors.ink,
            type: ThemeTypography(voice: .newsreader, ui: .plexMono, code: .plexMono, chrome: .plexMono,
                                  chromeItalic: false, chromeCase: .upper, chromeTracking: 0.08,
                                  stateScale: 11.0 / 17.0, userLine: .plexMono, userLineItalic: false),
            marking: .dashedBox, texture: .grid(16), ruleStyle: .solid, marginRule: .single,
            progress: .squareCells, listening: .zigzag,
            chrome: ThemeChrome(widgetRadius: 0, panelRadius: 0, borderWidth: 1, shadow: .none,
                                showsGlyph: false, micButton: .square, stampOverlay: true,
                                squareCorners: true, inputWell: false),
            copy: ThemeCopy(idleName: "Haku", hotkeyHint: "⌥ SPC", placeholder: "Type or hold ⌥ Space",
                            userPrefix: "›", listening: "listening"),
            density: density)
    }

    /// Legal pad — ruled 28 pt lines, red double margin, oxblood binding, pink highlighter.
    static func legalPad(density: DensityMetrics) -> Theme {
        let colors = ThemeColors.named("LegalPad")
        return Theme(
            id: .legalPad, scheme: .light, colors: colors,
            highlight: colors.highlight ?? .pink,
            type: marginType,
            marking: .band(top: 0.50, bottom: 0.92), texture: .ruled(28), ruleStyle: .solid, marginRule: .double,
            progress: .tally, listening: .squiggle(stroke: Strokes.squiggle, useBlueInk: true),
            chrome: ThemeChrome(widgetRadius: Radii.widget, panelRadius: Radii.panel, borderWidth: 1,
                                shadow: .legalPad, bindingWidget: 6, bindingPanel: 10,
                                showsGlyph: false, inputWell: false),
            copy: ThemeCopy(placeholder: "write, or hold ⌥ Space"),
            density: density)
    }

    /// Typewriter — Courier Prime everywhere, dashed rules, ribbon-red marking, block cursor.
    static func typewriter(density: DensityMetrics) -> Theme {
        let colors = ThemeColors.named("Typewriter")
        return Theme(
            id: .typewriter, scheme: .light, colors: colors,
            highlight: colors.highlight ?? .red,
            type: ThemeTypography(voice: .courierPrime, ui: .courierPrime, code: .courierPrime,
                                  chrome: .courierPrime, chromeItalic: false, chromeCase: .lower,
                                  chromeTracking: 0, stateScale: 14.0 / 17.0,
                                  userLine: .courierPrime, userLineItalic: false),
            marking: .ribbonText, texture: .none, ruleStyle: .dashed, marginRule: .dashed,
            progress: .bracketHashes, listening: .cursor,
            chrome: ThemeChrome(widgetRadius: Radii.widget, panelRadius: Radii.panel, borderWidth: 1,
                                shadow: .none, showsGlyph: false, micButton: .bracketText, inputWell: false),
            copy: ThemeCopy(idleName: "haku", hotkeyHint: "opt+space", placeholder: "type here_",
                            userPrefix: ">", headerDate: "dd.MM.yy"),
            density: density)
    }

    /// Kraft — speckled card stock, shipping-tag widget, white chalk band, stamp badge.
    static func kraft(density: DensityMetrics) -> Theme {
        let colors = ThemeColors.named("Kraft")
        return Theme(
            id: .kraft, scheme: .light, colors: colors,
            highlight: colors.highlight ?? .white,
            type: marginType,
            marking: .band(top: 0.45, bottom: 0.88), texture: .speckle, ruleStyle: .solid, marginRule: .single,
            progress: .stamp, listening: .squiggle(stroke: 1.8, useBlueInk: false),
            chrome: ThemeChrome(widgetRadius: Radii.panel, panelRadius: Radii.panel, borderWidth: 1,
                                shadow: .none, shippingTag: true, showsGlyph: false, stampOverlay: false,
                                inputWell: false),
            copy: ThemeCopy(placeholder: "write, or hold ⌥ Space"),
            density: density)
    }
}
