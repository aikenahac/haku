import AppKit
import SwiftUI
import XCTest
@testable import Haku

/// Renders the app icon (from the design's vector) into Haku/Resources/Assets.xcassets/AppIcon.appiconset.
/// Run when the logo or palette changes; the generated PNGs are committed.
@MainActor
final class IconExportTests: XCTestCase {
    func testExportAppIcon() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let set = root.appendingPathComponent("Haku/Resources/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try #"{"info":{"author":"xcode","version":1}}"#.write(to: set.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        var images: [[String: String]] = []
        for pt in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = pt * scale
                let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
                try render(px).write(to: set.appendingPathComponent(name))
                images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
            }
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: set.appendingPathComponent("Contents.json"))
    }

    /// macOS icon grid: 824/1024 tile with a soft drop shadow.
    private func render(_ px: Int) throws -> Data {
        let canvas = CGFloat(px)
        let tile = canvas * 824 / 1024
        let view = ZStack {
            AppIconView(theme: Theme.resolve(.daylight, scheme: .light))
                .frame(width: tile, height: tile)
                .shadow(color: .black.opacity(0.22), radius: canvas * 0.012, y: canvas * 0.01)
        }
        .frame(width: canvas, height: canvas)
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 1
        let img = try XCTUnwrap(r.cgImage)
        return try XCTUnwrap(NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]))
    }
}
