import AppKit
import SwiftUI

/// Color tokens resolved from `Colors.xcassets` (generated from tools/design-tokens/colors.json).
/// Margin tokens carry Any/Dark appearances (Daylight/Carbon); extra themes are fixed.
struct ThemeColors: Equatable, Sendable {
    /// Preview backdrop only; stands in for the desktop.
    let desk: Color
    /// Widget, panel and window surface.
    let paper: Color
    /// Input wells, selected rows, code/log blocks.
    let paper2: Color
    /// Primary text, filled buttons, icons.
    let ink: Color
    /// Labels, secondary text.
    let muted: Color
    /// Dividers and inactive strokes.
    let rule: Color
    /// Outer border of widget/panel/windows.
    let border: Color
    /// Links, margin notes, "running".
    let blueInk: Color
    /// Vertical margin rule in the panel.
    let marginLine: Color
    /// Errors and destructive warnings (always paired with a wavy underline or text).
    let error: Color
    /// Unfinished tally strokes.
    let tallyTodo: Color
    /// Text color drawn on top of a highlighter mark.
    let markInk: Color
    /// Shadow tint.
    let shadow: Color
    /// Theme marking color (fixed per extra theme; Margin uses the user's highlighter).
    let highlight: Color?
    let texture: Color?
    let texture2: Color?
    let binding: Color?
    let tagHole: Color?

    static func named(_ namespace: String) -> ThemeColors {
        func c(_ name: String) -> Color { Color("\(namespace)/\(name)", bundle: .main) }
        func opt(_ name: String) -> Color? {
            NSColor(named: "\(namespace)/\(name)", bundle: .main) == nil ? nil : c(name)
        }
        return ThemeColors(
            desk: c("desk"), paper: c("paper"), paper2: c("paper2"), ink: c("ink"), muted: c("muted"),
            rule: c("rule"), border: c("border"), blueInk: c("blueInk"), marginLine: c("marginLine"),
            error: c("error"), tallyTodo: c("tallyTodo"), markInk: c("markInk"), shadow: c("shadow"),
            highlight: opt("highlight"), texture: opt("texture"), texture2: opt("texture2"),
            binding: opt("binding"), tagHole: opt("tagHole"))
    }

    /// Light-mode canvas behind previews (#EFEBE1 in the mockups).
    static let canvas = Color("Margin/canvas", bundle: .main)
}

/// User-selectable highlighter colors (HANDOFF › Color: highlight).
enum HighlighterColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case yellow, mint, pink, sky
    var id: String { rawValue }
    var color: Color { Color("Highlighter/\(rawValue)", bundle: .main) }
    var label: String { rawValue.capitalized }
}
