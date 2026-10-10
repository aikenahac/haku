import AppKit
import SwiftUI
import XCTest
@testable import Haku

/// Renders the design boards to PNGs in build/snapshots/ for side-by-side review with the mockups.
@MainActor
final class PreviewSnapshotTests: XCTestCase {
    private var outDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/snapshots")
    }

    private func render<V: View>(_ name: String, @ViewBuilder _ view: () -> V) throws {
        let content = view()
            .environment(\.motionDisabled, true)
            .environment(\.staticRendering, true)
            .padding(64)
            .background(ThemeColors.canvas)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "render failed: \(name)")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(image.size.width, 100)
    }

    func testRenderBoards() throws {
        FontRegistry.registerBundledFonts()
        XCTAssertTrue(FontRegistry.isAvailable(.newsreader), "Newsreader not registered")
        XCTAssertTrue(FontRegistry.isAvailable(.atkinson))
        XCTAssertTrue(FontRegistry.isAvailable(.plexMono))
        XCTAssertTrue(FontRegistry.isAvailable(.courierPrime))

        try render("01-brand") { BrandBoard() }
        try render("02-margin-light-dark") {
            HStack(alignment: .top, spacing: 32) {
                WidgetPanelBoard(scheme: .light)
                WidgetPanelBoard(scheme: .dark)
            }
        }
        try render("03-extra-themes") { ExtraThemesBoard() }
        try render("04-widget-options") { WidgetOptionsBoard() }
        try render("05-highlighters") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(HighlighterColor.allCases) { h in
                    HStack(spacing: 24) {
                        WidgetView(state: .listening(level: 1, elapsed: 0)).theme(.resolve(.daylight, highlighter: h))
                        WidgetView(state: .listening(level: 1, elapsed: 0)).theme(.resolve(.carbon, highlighter: h))
                    }
                }
            }
        }
    }
}
