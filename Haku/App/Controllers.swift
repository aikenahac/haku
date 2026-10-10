import AppKit
import SwiftUI

/// The expanded panel window. Opens next to the widget.
@MainActor
final class PanelController {
    private let model: AppModel
    private let themes: ThemeManager
    private var host: PanelHost<AnyView>!
    weak var widget: WidgetController?
    private let margin = WidgetMetrics.windowMargin

    init(model: AppModel, themes: ThemeManager) {
        self.model = model
        self.themes = themes
        host = PanelHost(key: true) {
            AnyView(PanelRootView(onCollapse: { [weak self] in self?.hide() })
                .environment(model)
                .environment(themes))
        }
        host.panel.onEscape = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { host.panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let size = host.hosting.fittingSize
        host.panel.setContentSize(size)
        position(size: size)
        host.panel.makeKeyAndOrderFront(nil)
        host.panel.orderFrontRegardless()
    }

    func hide() { host.panel.orderOut(nil) }

    /// Below the widget when there's room, otherwise above; aligned to the widget's nearer side.
    private func position(size: NSSize) {
        guard let w = widget?.contentFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(w) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let content = NSSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        let gap: CGFloat = 10
        var x = w.midX > v.midX ? w.maxX - content.width : w.minX
        var y = w.minY - gap - content.height
        if y < v.minY { y = w.maxY + gap }
        if y + content.height > v.maxY { y = v.maxY - content.height }
        x = min(max(x, v.minX + 8), v.maxX - content.width - 8)
        y = max(y, v.minY + 8)
        host.panel.setFrameOrigin(NSPoint(x: x - margin, y: y - margin))
    }
}

struct PanelRootView: View {
    @Environment(AppModel.self) private var model
    var onCollapse: () -> Void

    var body: some View {
        let model = self.model
        let draft = Binding(get: { model.draft }, set: { model.draft = $0 })
        return ThemedRoot {
            ExpandedPanelView(
                messages: model.messages,
                notes: model.marginNotes,
                workflows: model.workflows.workflows.map(\.linkTitle),
                modelName: model.modelDisplayName,
                draft: draft,
                actions: PanelActions(
                    openTasks: { model.showTasks(nil) },
                    openSettings: { model.showSettings(nil) },
                    collapse: onCollapse,
                    attach: { chooseFiles() },
                    send: { _ in model.submitDraft() },
                    talkPressed: { down in down ? model.talkPressed() : model.talkReleased() },
                    runWorkflow: { model.runWorkflowFromUI(named: $0) },
                    showLog: { id in model.showTasks(id) },
                    cancelJob: { id in model.cancelJob(id) },
                    removeAttachment: { model.removeAttachment($0) },
                    pasteImage: { model.attach(image: $0) },
                    pasteFiles: { model.attach(urls: $0) }),
                pending: model.pendingAttachments,
                liveTranscript: model.voice.isListening ? model.voice.partial : nil,
                thinkingLabel: model.thinkingLabel)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.attach(urls: [url]) } }
                    }
                }
                return true
            }
            .padding(WidgetMetrics.windowMargin)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach files as context"
        NSApp.activate()
        if panel.runModal() == .OK { model.attach(urls: panel.urls) }
    }
}

/// Shows the confirmation slip under the widget and keeps it key for esc / ⏎.
@MainActor
final class ConfirmController {
    private let model: AppModel
    private let themes: ThemeManager
    private var host: PanelHost<AnyView>!
    weak var widget: WidgetController?

    init(model: AppModel, themes: ThemeManager) {
        self.model = model
        self.themes = themes
        host = PanelHost(key: true) {
            AnyView(ConfirmRootView().environment(model).environment(themes))
        }
        host.panel.level = .modalPanel
        host.panel.onEscape = { [weak model] in model?.confirmations.deny() }
        model.confirmations.onPresent = { [weak self] _ in self?.show() }
        model.confirmations.onDismiss = { [weak self] in self?.hide() }
    }

    func show() {
        DispatchQueue.main.async { [self] in
            let size = host.hosting.fittingSize
            host.panel.setContentSize(size)
            if let w = widget?.contentFrame, let screen = NSScreen.screens.first(where: { $0.frame.intersects(w) }) ?? NSScreen.main {
                let v = screen.visibleFrame
                let m = WidgetMetrics.windowMargin
                var x = w.midX > v.midX ? w.maxX - (size.width - 2 * m) : w.minX
                var y = w.minY - 10 - (size.height - 2 * m)
                if y < v.minY { y = w.maxY + 10 }
                x = min(max(x, v.minX + 8), v.maxX - size.width + 2 * m - 8)
                y = min(max(y, v.minY + 8), v.maxY - size.height + 2 * m)
                host.panel.setFrameOrigin(NSPoint(x: x - m, y: y - m))
            }
            host.panel.makeKeyAndOrderFront(nil)
            host.panel.orderFrontRegardless()
            model.confirmationPresented()
        }
    }

    func hide() { host.panel.orderOut(nil) }
}

struct ConfirmRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ThemedRoot {
            if let r = model.confirmations.current {
                ConfirmSlipView(center: model.confirmations, request: r, listening: model.voice.isListening,
                                onListConsequence: { cmd in
                                    Task {
                                        let out = await ShellRunner.run(cmd, timeout: 10).output
                                        let file = FileManager.default.temporaryDirectory.appendingPathComponent("haku-list.txt")
                                        try? out.write(to: file, atomically: true, encoding: .utf8)
                                        NSWorkspace.shared.open(file)
                                    }
                                },
                                onChooseFolder: {
                                    let p = NSOpenPanel()
                                    p.canChooseDirectories = true
                                    p.canChooseFiles = false
                                    p.directoryURL = URL(fileURLWithPath: model.confirmations.folder.expandingTilde)
                                    NSApp.activate()
                                    if p.runModal() == .OK, let u = p.url { model.confirmations.folder = u.path.abbreviatingHome }
                                })
                .id(r.id)
                .padding(WidgetMetrics.windowMargin)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }
}

/// Menu-bar item: card outline when idle, filled while live.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    var onMenu: () -> NSMenu = { NSMenu() }

    init(model: AppModel) {
        self.model = model
        item.button?.image = Self.glyph(filled: false)
        item.button?.toolTip = "Haku"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        observe { [weak self] in
            guard let self else { return }
            let live: Bool = {
                if case .idle = self.model.widgetState { return false }
                return true
            }()
            self.item.button?.image = Self.glyph(filled: live)
        }
    }

    @objc private func clicked() {
        let menu = onMenu()
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// Template image from the card path (viewBox 48).
    static func glyph(filled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { rect in
            let path = SVGPath.parse(GlyphPaths.card)
                .applying(CGAffineTransform(scaleX: rect.width / 48, y: rect.height / 48))
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path.cgPath)
            NSColor.black.set()
            if filled {
                ctx.fillPath()
            } else {
                ctx.setLineWidth(Strokes.glyphOutline * rect.width / 48)
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Builds the right-click / status-bar menu.
@MainActor
enum MenuBuilder {
    static func menu(model: AppModel, themes: ThemeManager, togglePanel: @escaping () -> Void,
                     showWorkflows: @escaping () -> Void, toggleWidget: @escaping () -> Void) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Open panel", key: "") { togglePanel() })
        m.addItem(ClosureMenuItem("Tasks", key: "") { model.showTasks(nil) })
        let flows = NSMenuItem(title: "Workflows", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for w in model.workflows.workflows { sub.addItem(ClosureMenuItem(w.name) { model.runWorkflowFromUI(w.id) }) }
        sub.addItem(.separator())
        sub.addItem(ClosureMenuItem("Edit workflows…") { showWorkflows() })
        flows.submenu = sub
        m.addItem(flows)
        m.addItem(ClosureMenuItem("Attach screenshot") { model.attachScreenshot() })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(model.settings.showWidget ? "Hide widget" : "Show widget") { toggleWidget() })
        m.addItem(ClosureMenuItem("Settings…", key: ",") { model.showSettings(nil) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Quit Haku", key: "q") { NSApp.terminate(nil) })
        return m
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
