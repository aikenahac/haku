import AppKit
import XCTest
@testable import Haku

/// HANDOFF › Contrast: all text tokens pass 4.5:1 on their paper. Keep it that way.
final class ContrastTests: XCTestCase {
    private func rgb(_ name: String, dark: Bool) throws -> (Double, Double, Double, Double) {
        let color = try XCTUnwrap(NSColor(named: name, bundle: .main), "missing color \(name)")
        var out: (Double, Double, Double, Double) = (0, 0, 0, 0)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        return out
    }

    private func luminance(_ c: (Double, Double, Double, Double)) -> Double {
        func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.0) + 0.7152 * ch(c.1) + 0.0722 * ch(c.2)
    }

    static func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    func testTextTokensPassAAOnPaper() throws {
        let cases: [(ns: String, dark: Bool)] = [
            ("Margin", false), ("Margin", true), ("Blueprint", true), ("LegalPad", false), ("Typewriter", false), ("Kraft", false),
        ]
        var failures: [String] = []
        for (ns, dark) in cases {
            for surface in ["paper", "paper2"] {
                let bg = luminance(try rgb("\(ns)/\(surface)", dark: dark))
                for token in ["ink", "muted", "blueInk", "error"] {
                    let r = Self.ratio(luminance(try rgb("\(ns)/\(token)", dark: dark)), bg)
                    // paper2 is a well for ink/muted text; links and errors sit on paper.
                    if surface == "paper2" && (token == "blueInk" || token == "error") { continue }
                    if r < 4.5 { failures.append("\(ns)\(dark ? " dark" : "") \(token) on \(surface): \(String(format: "%.2f", r))") }
                }
            }
        }
        XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testMarkInkOnHighlighters() throws {
        // Dark mode: text on the highlighter fill stays #1C1E24.
        let ink = luminance(try rgb("Margin/markInk", dark: true))
        for h in HighlighterColor.allCases {
            let r = Self.ratio(ink, luminance(try rgb("Highlighter/\(h.rawValue)", dark: true)))
            XCTAssertGreaterThanOrEqual(r, 4.5, "\(h) \(r)")
        }
    }
}
