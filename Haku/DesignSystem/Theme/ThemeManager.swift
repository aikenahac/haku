import AppKit
import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match system"
        }
    }
}

enum Density: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var metrics: DensityMetrics { self == .compact ? .compact : .comfortable }
    var label: String { rawValue.capitalized }
}

/// Owns every appearance setting from HANDOFF › Settings › Appearance, persists them in
/// UserDefaults, and publishes the resolved `Theme`. Changes apply live.
@MainActor
@Observable
final class ThemeManager {
    private enum Key {
        static let theme = "appearance.theme"
        static let mode = "appearance.mode"
        static let highlighter = "appearance.highlighter"
        static let shape = "appearance.widgetShape"
        static let size = "appearance.widgetSize"
        static let idleOpacity = "appearance.idleOpacity"
        static let idleAnimation = "appearance.idleAnimation"
        static let density = "appearance.density"
    }

    static let defaultIdleOpacity: Double = 0.6
    static let idleOpacityRange: ClosedRange<Double> = 0.35...1.0

    @ObservationIgnored private let defaults: UserDefaults

    /// Margin themes (Daylight/Carbon) follow `mode`; extra themes ignore it.
    var themeFamily: ThemeID { didSet { save(themeFamily.rawValue, Key.theme) } }
    var mode: AppearanceMode { didSet { save(mode.rawValue, Key.mode); applyAppAppearance() } }
    var highlighter: HighlighterColor { didSet { save(highlighter.rawValue, Key.highlighter) } }
    var widgetShape: WidgetShape { didSet { save(widgetShape.rawValue, Key.shape) } }
    var widgetSize: WidgetSize { didSet { save(widgetSize.rawValue, Key.size) } }
    var idleOpacity: Double { didSet { defaults.set(idleOpacity, forKey: Key.idleOpacity) } }
    /// Optional idle animation; off by default and always off under Reduce Motion.
    var idleAnimation: Bool { didSet { defaults.set(idleAnimation, forKey: Key.idleAnimation) } }
    var density: Density { didSet { save(density.rawValue, Key.density) } }
    /// The system appearance, kept current by `SystemAppearanceObserver`.
    var systemScheme: ColorScheme = .light

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func read<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            Self.readEnum(defaults, key) ?? fallback
        }
        themeFamily = read(Key.theme, ThemeID.daylight)
        mode = read(Key.mode, AppearanceMode.system)
        highlighter = read(Key.highlighter, HighlighterColor.yellow)
        widgetShape = read(Key.shape, WidgetShape.slip)
        widgetSize = read(Key.size, WidgetSize.medium)
        idleOpacity = defaults.object(forKey: Key.idleOpacity) as? Double ?? Self.defaultIdleOpacity
        idleAnimation = defaults.bool(forKey: Key.idleAnimation)
        density = read(Key.density, Density.comfortable)
        systemScheme = Self.currentSystemScheme()
    }

    /// The scheme the Margin theme renders in right now.
    var effectiveScheme: ColorScheme {
        if let fixed = themeFamily.fixedScheme { return fixed }
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme
        }
    }

    var theme: Theme {
        Theme.resolve(themeFamily, scheme: effectiveScheme, highlighter: highlighter, density: density.metrics)
    }

    var widgetMetrics: WidgetMetrics { .of(widgetSize) }

    /// The theme-grid entry that shows as selected.
    var selectedThemeID: ThemeID { theme.id }

    /// Picking Daylight or Carbon in the theme grid pins the mode to match.
    func select(_ id: ThemeID) {
        themeFamily = id
        switch id {
        case .daylight: mode = .light
        case .carbon: mode = .dark
        default: break
        }
    }

    func applyAppAppearance() {
        guard NSApp != nil else { return }
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    static func currentSystemScheme() -> ColorScheme {
        let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            ?? NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }

    private nonisolated static func readEnum<T: RawRepresentable>(_ d: UserDefaults, _ key: String) -> T? where T.RawValue == String {
        d.string(forKey: key).flatMap(T.init(rawValue:))
    }

    private func save(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
}
