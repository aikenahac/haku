import SwiftUI

@main
struct HakuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // v0 checkpoint: the design gallery is the only window. Features land after sign-off.
        Window("Haku — Design", id: "design-gallery") {
            DesignGallery()
                .environment(appDelegate.themeManager)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let themeManager = ThemeManager()

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        themeManager.applyAppAppearance()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
