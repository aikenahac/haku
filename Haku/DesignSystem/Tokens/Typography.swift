import AppKit
import CoreText
import SwiftUI

/// Bundled typefaces (all OFL). Fallbacks per HANDOFF: New York, SF Pro, SF Mono.
enum FontFamily: String, Sendable {
    case newsreader = "Newsreader"
    case atkinson = "Atkinson Hyperlegible"
    case plexMono = "IBM Plex Mono"
    case courierPrime = "Courier Prime"

    var fallbackDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .newsreader: .serif
        case .atkinson: .default
        case .plexMono, .courierPrime: .monospaced
        }
    }
}

/// Registers the bundled fonts once. `ATSApplicationFontsPath` covers the running app;
/// this also covers previews and the test host when the Info.plist key isn't honoured.
enum FontRegistry {
    nonisolated(unsafe) private static var registered = false

    static func registerBundledFonts(bundle: Bundle = .main) {
        guard !registered else { return }
        registered = true
        let dir = bundle.resourceURL?.appendingPathComponent("Fonts")
        guard let dir, let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func isAvailable(_ family: FontFamily) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family.rawValue) != nil
    }
}

enum FontFactory {
    /// Builds a font from a bundled family with weight + italic, falling back to the system design.
    static func font(_ family: FontFamily, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> Font {
        Font(nsFont(family, size: size, weight: weight, italic: italic))
    }

    static func nsFont(_ family: FontFamily, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        FontRegistry.registerBundledFonts()
        var traits: [NSFontDescriptor.TraitKey: Any] = [.weight: weight.rawValue]
        if italic { traits[.symbolic] = NSFontDescriptor.SymbolicTraits.italic.rawValue }
        let desc = NSFontDescriptor(fontAttributes: [.family: family.rawValue, .traits: traits])
        if FontRegistry.isAvailable(family), let f = NSFont(descriptor: desc, size: size), f.familyName == family.rawValue {
            return f
        }
        var fallback = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        fallback = fallback.withDesign(family.fallbackDesign) ?? fallback
        if italic { fallback = fallback.withSymbolicTraits(.italic) }
        return NSFont(descriptor: fallback, size: size) ?? .systemFont(ofSize: size)
    }
}

/// Semantic text roles. Sizes come from HANDOFF › Type and the mockup CSS;
/// the theme decides which family each role uses.
enum TextRole: Hashable, Sendable {
    /// "Haku" wordmark, Newsreader italic 500, 96, −0.02em.
    case wordmark
    /// Widget state word (Newsreader italic 17 at size M).
    case widgetState(CGFloat)
    /// Seal "h".
    case sealLetter
    /// Window titles (22, serif italic).
    case windowTitle
    /// Task / onboarding titles (24, serif 500).
    case pageTitle
    /// Panel header "Haku" (serif italic 18) and settings section headings.
    case heading
    /// Conversation body (serif, density-driven size).
    case body(CGFloat)
    /// List items, nav, steps, onboarding copy (serif 15).
    case listItem
    /// `.lbl`: serif italic 14 muted.
    case label
    /// Margin notes, statuses (serif italic 13).
    case note
    /// `.lnk`: serif 14 (13 in compact spots).
    case link(CGFloat)
    /// `.sc`: sans 11 / 10.5 uppercase, +0.07em.
    case smallCaps(CGFloat)
    /// UI text: segments, checkboxes, field labels (sans 13).
    case ui
    /// Buttons: sans 700 13.
    case button
    /// Paths, logs, code, shortcuts.
    case mono(CGFloat)
    /// Mono with weight 500 (key caps).
    case monoMedium(CGFloat)
}

enum TypeScale {
    static let wordmark: CGFloat = 96
    static let windowTitle: CGFloat = 22
    static let pageTitle: CGFloat = 24
    static let heading: CGFloat = 18
    static let panelBody: CGFloat = 16
    static let listItem: CGFloat = 15
    static let label: CGFloat = 14
    static let note: CGFloat = 13
    static let link: CGFloat = 14
    static let linkSmall: CGFloat = 13
    static let smallCaps: CGFloat = 11
    static let smallCapsTight: CGFloat = 10.5
    static let ui: CGFloat = 13
    static let monoInput: CGFloat = 12.5
    static let monoCode: CGFloat = 12
    static let monoLog: CGFloat = 11.5
    static let monoSmall: CGFloat = 11
    static let monoPath: CGFloat = 10.5
    static let monoCaption: CGFloat = 10
    static let inlinePath: CGFloat = 13

    static let smallCapsTracking: CGFloat = 0.07   // em
    static let wordmarkTracking: CGFloat = -0.02   // em
    static let titleLineHeight: CGFloat = 1.1
    static let noteLineHeight: CGFloat = 1.35
    static let logLineHeight: CGFloat = 1.7
    static let codeLineHeight: CGFloat = 1.65
    static let underlineOffset: CGFloat = 3
    static let wavyOffset: CGFloat = 5
}
