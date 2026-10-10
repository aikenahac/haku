import SwiftUI

/// Animation timings from the mockup keyframes. Every use must be gated by
/// `accessibilityReduceMotion` (see `MotionGate`).
enum Motion {
    /// Thinking dots: fade .2 → 1 → .2, 1.2 s loop, staggered 0.2 s.
    static let dotsPeriod: Double = 1.2
    static let dotsStagger: Double = 0.2
    static let dotsMinOpacity: Double = 0.2
    /// Listening squiggle redraw (stroke trim), draws over first 60% of 1.6 s.
    static let writePeriod: Double = 1.6
    /// Speaking underline draws in, 2.2 s loop.
    static let underlinePeriod: Double = 2.2
    /// Fraction of a write loop spent drawing; the rest holds the full stroke.
    static let writeDrawFraction: Double = 0.6
    /// Idle opacity snap.
    static let opacitySnap: Animation = .easeOut(duration: 0.15)
    static let stateChange: Animation = .easeInOut(duration: 0.18)
    /// Block cursor blink (Typewriter listening).
    static let cursorBlink: Double = 1.0

    /// Ease-in-out progress of a "write" keyframe (0→1 over `drawFraction`, then hold).
    static func writeProgress(time: Double, period: Double, drawFraction: Double = writeDrawFraction) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let p = min(1, phase / drawFraction)
        return p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    /// Opacity of dot `index` in the thinking loop (keyframes 0/100% = .2, 40% = 1, ease-in-out).
    static func dotOpacity(time: Double, index: Int) -> Double {
        let t = (time - Double(index) * dotsStagger).truncatingRemainder(dividingBy: dotsPeriod)
        let phase = (t < 0 ? t + dotsPeriod : t) / dotsPeriod
        let rise = phase < 0.4 ? phase / 0.4 : 1 - (phase - 0.4) / 0.6
        let eased = rise < 0.5 ? 2 * rise * rise : 1 - pow(-2 * rise + 2, 2) / 2
        return dotsMinOpacity + (1 - dotsMinOpacity) * eased
    }
}
