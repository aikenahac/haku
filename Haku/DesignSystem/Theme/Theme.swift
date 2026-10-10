import AppKit
import SwiftUI

enum ThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    case daylight, carbon, blueprint, legalPad, typewriter, kraft
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daylight: "Daylight"
        case .carbon: "Carbon"
        case .blueprint: "Blueprint"
        case .legalPad: "Legal pad"
        case .typewriter: "Typewriter"
        case .kraft: "Kraft"
        }
    }

    /// Daylight and Carbon are the two appearances of the base Margin theme.
    var isMargin: Bool { self == .daylight || self == .carbon }

    /// Extra themes have one fixed appearance; system controls render in it.
    var fixedScheme: ColorScheme? {
        switch self {
        case .daylight, .carbon: nil
        case .blueprint: .dark
        case .legalPad, .typewriter, .kraft: .light
        }
    }
}

/// How marked text ("listening", key phrases) is drawn.
enum MarkingStyle: Equatable, Sendable {
    /// A highlighter band behind the lower part of the line (fractions of line height).
    case band(top: CGFloat, bottom: CGFloat)
    /// A full fill behind the text; text switches to `markInk` (Carbon).
    case fill
    /// Dashed outline box, 3 pt offset (Blueprint).
    case dashedBox
    /// Text recolored in ribbon red, no fill (Typewriter).
    case ribbonText
}

enum TextureStyle: Equatable, Sendable {
    case none
    /// Square grid lines (Blueprint, 16 pt at 8%).
    case grid(CGFloat)
    /// Horizontal ruled lines (Legal pad, 28 pt).
    case ruled(CGFloat)
    /// Two offset dot layers (Kraft, 7 pt and 11 pt).
    case speckle
}

enum RuleStyle: Equatable, Sendable { case solid, dashed }
enum MarginRuleStyle: Equatable, Sendable { case single, double, dashed }
enum ProgressStyle: Equatable, Sendable { case tally, squareCells, bracketHashes, stamp }

enum ListeningStyle: Equatable, Sendable {
    /// Hand-drawn ink squiggle, driven by mic level.
    case squiggle(stroke: CGFloat, useBlueInk: Bool)
    /// Straight-segment zigzag (Blueprint).
    case zigzag
    /// "listening_" + block cursor + elapsed timer (Typewriter).
    case cursor
}

enum ChromeCase: Equatable, Sendable { case none, upper, lower }
enum MicButtonStyle: Equatable, Sendable { case round, square, bracketText }

struct ThemeTypography: Equatable, Sendable {
    /// Haku's voice: conversation, headings, list items.
    var voice: FontFamily
    /// UI text, buttons, small caps.
    var ui: FontFamily
    /// Paths, logs, code.
    var code: FontFamily
    /// State words and labels.
    var chrome: FontFamily
    var chromeItalic: Bool
    var chromeCase: ChromeCase
    var chromeTracking: CGFloat
    /// Widget state size relative to the Margin size (Blueprint 11/17, Typewriter 14/17).
    var stateScale: CGFloat
    /// User lines in the conversation use this family (Blueprint uses mono).
    var userLine: FontFamily
    var userLineItalic: Bool
}

struct ThemeChrome: Equatable, Sendable {
    var widgetRadius: CGFloat
    var panelRadius: CGFloat
    var borderWidth: CGFloat
    var shadow: ShadowStyle
    /// Oxblood binding strip height on the widget and the panel (Legal pad).
    var bindingWidget: CGFloat = 0
    var bindingPanel: CGFloat = 0
    /// Kraft shipping tag: punched hole + rounded right end.
    var shippingTag: Bool = false
    /// Card glyph at the start of the widget (Margin only in the mockups).
    var showsGlyph: Bool = true
    var micButton: MicButtonStyle = .round
    /// The stamp badge overlay for running-job count.
    var stampOverlay: Bool = true
    /// Square corners everywhere (Blueprint).
    var squareCorners: Bool = false
    /// The input row sits on paper2 (Margin) or on the paper itself.
    var inputWell: Bool = true
}

/// How the talk hotkey is written in the widget: "⌃⌥ SPACE", "⌃⌥ SPC" or "ctrl+opt+space".
enum HotkeyHintStyle: Equatable, Sendable { case symbols, compact, words }

struct ThemeCopy: Equatable, Sendable {
    var idleName: String = "Haku"
    var hotkeyStyle: HotkeyHintStyle = .symbols
    /// `{key}` is replaced with the current talk hotkey.
    var placeholder: String = "Write, or hold {key} to speak"
    var userPrefix: String = "—"
    var listening: String = "listening"
    var thinking: String = "thinking"
    var speaking: String = "speaking"
    /// Date in the panel header.
    var headerDate: String = "EEE d MMM"

    static let defaultKeys = ["⌃", "⌥", "Space"]

    func hotkeyHint(_ keys: [String]) -> String {
        let mods = keys.dropLast(), key = keys.last ?? ""
        switch hotkeyStyle {
        case .symbols: return mods.joined() + " " + key.uppercased()
        case .compact: return mods.joined() + " " + (key == "Space" ? "SPC" : key.uppercased())
        case .words:
            let names = ["⌃": "ctrl", "⌥": "opt", "⇧": "shift", "⌘": "cmd"]
            return (mods.map { names[$0] ?? $0 } + [key.lowercased()]).joined(separator: "+")
        }
    }

    func placeholder(_ keys: [String]) -> String {
        placeholder.replacingOccurrences(of: "{key}", with: keys.dropLast().joined() + " " + (keys.last ?? ""))
    }
}

private struct TalkKeysKey: EnvironmentKey { static let defaultValue = ThemeCopy.defaultKeys }
extension EnvironmentValues {
    /// The current hold-to-talk shortcut, for hints and placeholders.
    var talkKeys: [String] {
        get { self[TalkKeysKey.self] }
        set { self[TalkKeysKey.self] = newValue }
    }
}

/// A fully resolved theme: one value per (theme, appearance). Injected via `\.theme`.
struct Theme: Equatable, Sendable {
    let id: ThemeID
    let scheme: ColorScheme
    let colors: ThemeColors
    /// The active marking color (user highlighter for Margin, fixed otherwise).
    let highlight: Color
    let type: ThemeTypography
    let marking: MarkingStyle
    let texture: TextureStyle
    let ruleStyle: RuleStyle
    let marginRule: MarginRuleStyle
    let progress: ProgressStyle
    let listening: ListeningStyle
    let chrome: ThemeChrome
    let copy: ThemeCopy
    let density: DensityMetrics

    var isMargin: Bool { id.isMargin }

    // MARK: Fonts

    func font(_ role: TextRole) -> Font {
        let s = spec(role)
        return FontFactory.font(s.family, size: s.size, weight: s.weight, italic: s.italic)
    }

    func nsFont(_ role: TextRole) -> NSFont {
        let s = spec(role)
        return FontFactory.nsFont(s.family, size: s.size, weight: s.weight, italic: s.italic)
    }

    /// Tracking in points for a role.
    func tracking(_ role: TextRole) -> CGFloat {
        let s = spec(role)
        return s.trackingEm * s.size
    }

    func textCase(_ role: TextRole) -> Text.Case? {
        switch spec(role).textCase {
        case .none: nil
        case .upper: .uppercase
        case .lower: .lowercase
        }
    }

    struct FontSpec {
        var family: FontFamily
        var size: CGFloat
        var weight: NSFont.Weight = .regular
        var italic = false
        var trackingEm: CGFloat = 0
        var textCase: ChromeCase = .none
    }

    func spec(_ role: TextRole) -> FontSpec {
        let t = type
        let chrome = FontSpec(family: t.chrome, size: 0, italic: t.chromeItalic,
                              trackingEm: t.chromeTracking, textCase: t.chromeCase)
        func chromeSized(_ size: CGFloat) -> FontSpec { var c = chrome; c.size = size; return c }
        switch role {
        case .wordmark:
            return FontSpec(family: .newsreader, size: TypeScale.wordmark, weight: .medium, italic: true,
                            trackingEm: TypeScale.wordmarkTracking)
        case .widgetState(let size):
            return chromeSized(size * t.stateScale)
        case .sealLetter:
            return FontSpec(family: t.voice, size: WidgetMetrics.sealLetter, italic: t.voice == .newsreader)
        case .windowTitle:
            return chromeSized(TypeScale.windowTitle)
        case .pageTitle:
            return FontSpec(family: t.voice, size: TypeScale.pageTitle, weight: .medium)
        case .heading:
            return chromeSized(TypeScale.heading)
        case .body(let size):
            return FontSpec(family: t.voice, size: size)
        case .listItem:
            return FontSpec(family: t.voice, size: TypeScale.listItem)
        case .label:
            return chromeSized(TypeScale.label)
        case .note:
            return FontSpec(family: t.voice, size: TypeScale.note, italic: t.voice == .newsreader)
        case .link(let size):
            return FontSpec(family: t.voice, size: size)
        case .smallCaps(let size):
            return FontSpec(family: t.ui, size: size, trackingEm: TypeScale.smallCapsTracking, textCase: .upper)
        case .ui:
            return FontSpec(family: t.ui, size: TypeScale.ui)
        case .button:
            return FontSpec(family: t.ui, size: TypeScale.ui, weight: .bold)
        case .mono(let size):
            return FontSpec(family: t.code, size: size)
        case .monoMedium(let size):
            return FontSpec(family: t.code, size: size, weight: .medium)
        }
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .resolve(.daylight)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects a theme and pins the color scheme so asset colors resolve to the same appearance.
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .environment(\.colorScheme, theme.scheme)
    }
}
