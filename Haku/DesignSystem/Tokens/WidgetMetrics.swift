import CoreGraphics

enum WidgetSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small = "S", medium = "M", large = "L"
    var id: String { rawValue }
}

enum WidgetShape: String, CaseIterable, Codable, Sendable, Identifiable {
    case slip, indexTab, seal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slip: "Slip"
        case .indexTab: "Index tab"
        case .seal: "Seal"
        }
    }
}

/// Floating widget geometry (HANDOFF › Floating widget, Margin-Themes › Size).
struct WidgetMetrics: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let glyph: CGFloat
    let stateFont: CGFloat
    let smallCaps: CGFloat
    let linkFont: CGFloat
    let paddingLeading: CGFloat
    let paddingTrailing: CGFloat
    let gap: CGFloat
    let squiggle: CGSize
    let underline: CGSize
    let dot: CGFloat
    let tally: CGSize

    static func of(_ size: WidgetSize) -> WidgetMetrics {
        switch size {
        case .small:
            WidgetMetrics(width: 200, height: 36, glyph: 14, stateFont: 14, smallCaps: 10, linkFont: 12,
                          paddingLeading: 10, paddingTrailing: 12, gap: 8,
                          squiggle: CGSize(width: 68, height: 20), underline: CGSize(width: 58, height: 5),
                          dot: 3.5, tally: CGSize(width: 36, height: 13))
        case .medium:
            WidgetMetrics(width: 252, height: 46, glyph: 18, stateFont: 17, smallCaps: 11, linkFont: 13,
                          paddingLeading: 12, paddingTrailing: 14, gap: 10,
                          squiggle: CGSize(width: 84, height: 24), underline: CGSize(width: 70, height: 6),
                          dot: 4, tally: CGSize(width: 44, height: 16))
        case .large:
            WidgetMetrics(width: 300, height: 56, glyph: 22, stateFont: 21, smallCaps: 12, linkFont: 15,
                          paddingLeading: 14, paddingTrailing: 16, gap: 12,
                          squiggle: CGSize(width: 100, height: 28), underline: CGSize(width: 86, height: 7),
                          dot: 5, tally: CGSize(width: 52, height: 19))
        }
    }

    /// Seal: 52 pt round stamp, 40 pt inner ring, italic "h" at 20.
    static let sealDiameter: CGFloat = 52
    static let sealRing: CGFloat = 40
    static let sealLetter: CGFloat = 20
    /// Index tab: 60×16 tab on the top-left, 3/8 top radii.
    static let tabSize = CGSize(width: 60, height: 16)
    static let tabOverlap: CGFloat = 2
    /// Stamp badge (running-jobs count): 24 pt ring, rotated −10°, offset −10/−10.
    static let stampDiameter: CGFloat = 24
    static let stampOffset: CGFloat = 10
    static let stampRotation: Double = -10
    /// Kraft shipping tag: 9 pt punched hole 11 pt from the left; 30 pt leading inset; 22 pt right radius.
    static let tagHole: CGFloat = 9
    static let tagHoleInset: CGFloat = 11
    static let tagLeading: CGFloat = 30
    static let tagEndRadius: CGFloat = 22
    /// Extra space around the widget content in its window so the shadow and stamp aren't clipped.
    static let windowMargin: CGFloat = 24
}

/// Expanded panel geometry (HANDOFF › Expanded panel).
enum PanelMetrics {
    static let size = CGSize(width: 460, height: 640)
    static let headerHeight: CGFloat = 52
    static let headerPadding = (leading: CGFloat(16), trailing: CGFloat(10))
    static let marginWidth: CGFloat = 128
    static let marginPadding = (h: CGFloat(12), v: CGFloat(18))
    static let marginNoteTopOffset: CGFloat = 44
    static let iconButton: CGFloat = 28
    static let icon: CGFloat = 16
    static let micButton: CGFloat = 36
    static let inputHeight: CGFloat = 36
    static let inputFont: CGFloat = 16
    static let inputPadding = (top: CGFloat(12), leading: CGFloat(16), bottom: CGFloat(14), trailing: CGFloat(12))
    static let workflowsPadding = (h: CGFloat(16), v: CGFloat(10))
    /// Taped photo attachment.
    static let photoPadding: CGFloat = 6
    static let photoRotation: Double = -1.5
    static let photoThumb = CGSize(width: 132, height: 70)
    static let tape = CGSize(width: 44, height: 12)
    static let tapeOffset: CGFloat = -7
    static let tapeOpacity: Double = 0.55
}
