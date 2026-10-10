import CoreGraphics

/// Spacing on a 2/4 pt base (HANDOFF › Shape & spacing).
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s18: CGFloat = 18
    static let s20: CGFloat = 20
    static let s22: CGFloat = 22
    static let s24: CGFloat = 24
    static let s28: CGFloat = 28
    static let s32: CGFloat = 32
    static let s40: CGFloat = 40
    static let s44: CGFloat = 44

    /// Window padding 18–22.
    static let windowPadding: CGFloat = 20
}

/// Corner radii. No pills in this direction except the seal widget.
enum Radii {
    static let widget: CGFloat = 3
    static let button: CGFloat = 3
    static let panel: CGFloat = 4
    static let iconButton: CGFloat = 4
    static let mark: CGFloat = 1
}

/// Hairline and stroke widths used across surfaces.
enum Strokes {
    static let hairline: CGFloat = 1
    static let marginRule: CGFloat = 1.5
    static let stamp: CGFloat = 1.5
    static let squiggle: CGFloat = 1.6
    static let underline: CGFloat = 1.4
    static let tally: CGFloat = 1.6
    static let wavy: CGFloat = 1.5
    static let inputUnderline: CGFloat = 1
    /// Glyph outline stroke in the 48-unit viewBox (error state, menu bar idle).
    static let glyphOutline: CGFloat = 4
}

/// Conversation spacing per density option (Margin-Themes › Density).
struct DensityMetrics: Equatable, Sendable {
    let bodySize: CGFloat
    let lineHeight: CGFloat      // multiple of size
    let messageGap: CGFloat
    let bodyPaddingH: CGFloat
    let bodyPaddingV: CGFloat

    /// Comfortable matches the expanded panel mockup (16 / 1.45 / gap 18 / 18–20 padding).
    static let comfortable = DensityMetrics(bodySize: 16, lineHeight: 1.45, messageGap: 18, bodyPaddingH: 19, bodyPaddingV: 18)
    /// Compact from the density sample (14 / 1.3 / gap 4 / 8×12 padding).
    static let compact = DensityMetrics(bodySize: 14, lineHeight: 1.3, messageGap: 4, bodyPaddingH: 12, bodyPaddingV: 8)
}
