import AppKit
import SwiftUI
import XCTest
@testable import Haku

/// Renders the README promo images into docs/images/ from the real design components.
/// Re-run after visual changes: `xcodebuild test -only-testing:HakuTests/PromoImageTests`.
@MainActor
final class PromoImageTests: XCTestCase {
    private var outDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/images")
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func save<V: View>(_ name: String, scale: CGFloat = 2, in dir: URL? = nil, @ViewBuilder _ view: () -> V) throws {
        FontRegistry.registerBundledFonts()
        let content = view()
            .environment(\.motionDisabled, true)
            .environment(\.staticRendering, true)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: content)
        r.scale = scale
        let cg = try XCTUnwrap(r.cgImage, "render failed: \(name)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let dir = dir ?? outDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func testRenderPromoImages() throws {
        let light = Theme.resolve(.daylight)
        let dark = Theme.resolve(.carbon)

        // Hero: wordmark + tagline, the widget, and the panel in light and dark.
        try save("hero") {
            VStack(alignment: .leading, spacing: 44) {
                HStack(alignment: .center, spacing: 28) {
                    CardGlyph(color: light.colors.ink, highlight: light.highlight, highlightTilt: -3, paperLine: light.colors.paper)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 10) {
                        (Text("Ha") + Text("ku").marked(light))
                            .font(light.font(.wordmark)).tracking(light.tracking(.wordmark))
                            .foregroundStyle(light.colors.ink)
                            .textRenderer(InkTextRenderer(marking: .band(top: 0.55, bottom: 0.88), markColor: light.highlight,
                                                          boxColor: light.colors.ink, errorColor: light.colors.error))
                        Text("A local voice assistant and task dispatcher for macOS.")
                            .font(FontFactory.font(.newsreader, size: 26, italic: true))
                            .foregroundStyle(light.colors.muted)
                    }
                }
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach([WidgetState.idle, .listening(level: 1, elapsed: 3), .thinking,
                                 .agentRunning(agent: "Claude Code", done: 2, total: 5, jobs: 2)], id: \.accessibilityDescription) { s in
                            WidgetView(state: s)
                        }
                    }
                    .padding(.top, 20)
                    PanelSample().theme(light)
                    PanelSample().theme(dark)
                }
            }
            .padding(64)
            .background(ThemeColors.canvas)
        }

        // The six widget states, light and dark.
        try save("widget-states") {
            HStack(alignment: .top, spacing: 32) {
                WidgetPanelBoard(scheme: .light, showPanel: false)
                WidgetPanelBoard(scheme: .dark, showPanel: false)
            }
            .padding(48)
            .background(ThemeColors.canvas)
        }

        // Confirmation slips: nothing runs without a yes.
        let center = ConfirmationCenter()
        center.folder = "~/haku/devenv"
        center.agent = .claude
        center.edits = .askFirst
        try save("confirm") {
            HStack(alignment: .top, spacing: 28) {
                ConfirmSlipView(center: center, request: ConfirmationRequest(
                    kind: .shell(command: "find ~/Downloads -name \"*.dmg\" -mtime +30 -delete", cwd: "~/Downloads"),
                    source: "Shell command · workflow “Tidy Downloads”", question: "Run this command?",
                    consequences: [.init(text: "Permanently deletes 7 files", destructive: true, listCommand: "find ~/Downloads -name \"*.dmg\" -mtime +30 -print")],
                    alwaysAllowLabel: "Don't ask again for this workflow"))
                .theme(light)
                ConfirmSlipView(center: center, request: ConfirmationRequest(
                    kind: .agent(prompt: "Run the devenv tests and tell me what's failing.", agent: .claude, folder: "~/haku/devenv", edits: .askFirst),
                    source: "Agent delegation", question: "Hand this to Claude Code?"))
                .theme(dark)
            }
            .padding(56)
            .background(ThemeColors.canvas)
        }

        // Themes and widget options.
        try save("themes", scale: 1.5) {
            ExtraThemesBoard().padding(56).background(ThemeColors.canvas)
        }
        try save("widget-options", scale: 1.5) {
            WidgetOptionsBoard().padding(56).background(ThemeColors.canvas)
        }
    }

    /// The Finder window background for Haku.dmg, at 1x and 2x (merged into a TIFF by tools/package-dmg.sh).
    func testRenderDMGBackground() throws {
        let dir = repoRoot.appendingPathComponent("tools/dmg")
        try save("background", scale: 1, in: dir) { DMGBackground() }
        try save("background@2x", scale: 2, in: dir) { DMGBackground() }
    }
}

/// 660×400 Finder window art. Icons sit at (170, 196) and (490, 196), set in tools/package-dmg.sh.
private struct DMGBackground: View {
    private let theme = Theme.resolve(.daylight)

    var body: some View {
        let c = theme.colors
        ZStack(alignment: .topLeading) {
            c.desk
            ZStack(alignment: .topLeading) {
                Rectangle().fill(c.marginLine).frame(width: 1).padding(.leading, 40)
                HStack(spacing: 12) {
                    CardGlyph(color: c.ink, highlight: theme.highlight, highlightTilt: -3, paperLine: c.paper)
                        .frame(width: 34, height: 34)
                    (Text("Ha") + Text("ku").marked(theme))
                        .font(FontFactory.font(.newsreader, size: 34, weight: .medium, italic: true))
                        .tracking(-0.6)
                        .foregroundStyle(c.ink)
                        .textRenderer(InkTextRenderer(marking: .band(top: 0.55, bottom: 0.88), markColor: theme.highlight,
                                                      boxColor: c.ink, errorColor: c.error))
                }
                .offset(x: 58, y: 22)
                DragArrow(ink: c.ink, highlight: theme.highlight)
                    .frame(width: 150, height: 44)
                    .offset(x: 252 - 16, y: 174 - 16)
                Text("drag Haku into Applications")
                    .font(FontFactory.font(.newsreader, size: 17, italic: true))
                    .foregroundStyle(c.muted)
                    .frame(width: 260)
                    .offset(x: 330 - 16 - 130, y: 214 - 16)
                Text("FIRST LAUNCH ON ANOTHER MAC: RIGHT-CLICK › OPEN")
                    .font(FontFactory.font(.plexMono, size: 10, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(c.muted)
                    .frame(width: 628)
                    .offset(y: 336)
            }
            .frame(width: 628, height: 368, alignment: .topLeading)
            .paperSurface(radius: 6)
            .padding(16)
        }
        .frame(width: 660, height: 400)
        .theme(theme)
    }
}

/// A hand-drawn ink arrow over a tilted highlighter stroke.
private struct DragArrow: View {
    let ink: Color
    let highlight: Color

    var body: some View {
        ZStack {
            Rectangle().fill(highlight.opacity(0.85))
                .frame(width: 112, height: 13)
                .rotationEffect(.degrees(-3))
                .offset(x: -6, y: 4)
            Path { p in
                p.move(to: CGPoint(x: 6, y: 26))
                p.addCurve(to: CGPoint(x: 140, y: 20), control1: CGPoint(x: 44, y: 12), control2: CGPoint(x: 96, y: 32))
                p.move(to: CGPoint(x: 126, y: 9))
                p.addQuadCurve(to: CGPoint(x: 141, y: 20), control: CGPoint(x: 134, y: 16))
                p.addQuadCurve(to: CGPoint(x: 127, y: 32), control: CGPoint(x: 133, y: 25))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }
}
