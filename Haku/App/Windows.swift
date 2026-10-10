import AppKit
import Observation
import SwiftUI

/// Borderless, always-on-top, non-activating panel used for the widget, expanded panel and slips.
final class FloatingPanel: NSPanel {
    var allowsKey = false
    var onEscape: (() -> Void)?

    init(contentRect: NSRect = .zero, key: Bool) {
        allowsKey = key
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = !key
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }
}

/// Re-runs `apply` whenever any observable value it reads changes.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeChanges(apply) }
    }
}

/// Injects the current theme and keeps the ThemeManager's idea of the system appearance fresh.
struct ThemedRoot<Content: View>: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.colorScheme) private var systemScheme
    @State private var talkKeys = HotkeyManager.talkKeys
    @ViewBuilder var content: Content

    var body: some View {
        content
            .theme(themes.theme)
            .environment(\.talkKeys, talkKeys)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"))) { _ in
                talkKeys = HotkeyManager.talkKeys
            }
            .onAppear { themes.systemScheme = systemScheme }
            .onChange(of: systemScheme) { _, s in if themes.mode == .system { themes.systemScheme = s } }
    }
}

/// Hosts SwiftUI in a borderless panel and keeps the window sized to the view.
@MainActor
final class PanelHost<Content: View> {
    let panel: FloatingPanel
    let hosting: NSHostingView<Content>

    init(key: Bool, @ViewBuilder content: () -> Content) {
        panel = FloatingPanel(key: key)
        hosting = NSHostingView(rootView: content())
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
    }
}

/// Standard titled windows (Tasks, Settings, Workflows, Onboarding) with a paper look.
@MainActor
final class AppWindow {
    let window: NSWindow
    private var closeObserver: Any?

    init<V: View>(title: String, size: NSSize, minSize: NSSize? = nil, @ViewBuilder content: () -> V) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: content())
        window.setContentSize(size)
        if let minSize { window.contentMinSize = minSize }
        window.center()
        window.setFrameAutosaveName("haku.\(title)")
        // The design draws its own header with a close button.
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
