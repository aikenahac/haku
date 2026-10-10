import SwiftUI

/// One CSS-style box-shadow layer. `spread` is honoured (SwiftUI's `.shadow` can't do it),
/// which matters for the paper shadow's −10 spread.
struct ShadowLayer: Equatable, Sendable {
    let opacity: Double
    let x: CGFloat
    let y: CGFloat
    let blur: CGFloat
    let spread: CGFloat
    /// Inset hairline layers use the paper's top edge instead of a drop shadow.
    var inset: Bool = false
    /// When true the layer is tinted white instead of the theme shadow color.
    var light: Bool = false
}

/// Shadow presets (HANDOFF › Shape & spacing; Margin-Themes for Legal pad).
enum ShadowStyle: Equatable, Sendable {
    /// Daylight: `0 1 0 /6%`, `0 8 18 -10 /40%` in warm brown.
    case paperLight
    /// Carbon: inset `0 1 0 rgba(255,255,255,.03)`, `0 12 24 -12 /85%` black.
    case paperDark
    /// Legal pad: `0 6 14 -8 rgba(90,70,0,.45)`.
    case legalPad
    /// Seal: `0 8 18 -10 /40%`.
    case seal
    case none

    var layers: [ShadowLayer] {
        switch self {
        case .paperLight:
            [ShadowLayer(opacity: 0.06, x: 0, y: 1, blur: 0, spread: 0),
             ShadowLayer(opacity: 0.40, x: 0, y: 8, blur: 18, spread: -10)]
        case .paperDark:
            [ShadowLayer(opacity: 0.03, x: 0, y: 1, blur: 0, spread: 0, inset: true, light: true),
             ShadowLayer(opacity: 0.85, x: 0, y: 12, blur: 24, spread: -12)]
        case .legalPad:
            [ShadowLayer(opacity: 0.45, x: 0, y: 6, blur: 14, spread: -8)]
        case .seal:
            [ShadowLayer(opacity: 0.40, x: 0, y: 8, blur: 18, spread: -10)]
        case .none:
            []
        }
    }
}
