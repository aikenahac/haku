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

    private func save<V: View>(_ name: String, scale: CGFloat = 2, @ViewBuilder _ view: () -> V) throws {
        FontRegistry.registerBundledFonts()
        let content = view()
            .environment(\.motionDisabled, true)
            .environment(\.staticRendering, true)
            .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: content)
        r.scale = scale
        let cg = try XCTUnwrap(r.cgImage, "render failed: \(name)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
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
}
