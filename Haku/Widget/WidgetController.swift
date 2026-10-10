import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns the floating widget window: position, edge snapping, gestures, drops, menu.
@MainActor
final class WidgetController {
    private let model: AppModel
    private let themes: ThemeManager
    private var host: PanelHost<AnyView>!
    var onMenu: () -> NSMenu = { NSMenu() }

    private static let originKey = "widget.origin"
    private let margin = WidgetMetrics.windowMargin
    private let snapDistance: CGFloat = 28

    init(model: AppModel, themes: ThemeManager) {
        self.model = model
        self.themes = themes
        host = PanelHost(key: false) {
            AnyView(WidgetRootView(controller: self)
                .environment(model)
                .environment(themes))
        }
        host.panel.isFloatingPanel = true
        host.panel.acceptsMouseMovedEvents = true
    }

    var window: NSWindow { host.panel }

    func show() {
        sizeToFit()
        restorePosition()
        host.panel.orderFrontRegardless()
    }

    func hide() { host.panel.orderOut(nil) }

    /// The widget's visible rect (window minus the shadow margin), in screen coordinates.
    var contentFrame: NSRect { host.panel.frame.insetBy(dx: margin, dy: margin) }

    func sizeToFit() {
        let size = host.hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var f = host.panel.frame
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height   // keep the top edge anchored
        host.panel.setFrame(f, display: true)
    }

    // MARK: Position

    private func restorePosition() {
        if let s = UserDefaults.standard.string(forKey: Self.originKey) {
            let p = NSPointFromString(s)
            host.panel.setFrameOrigin(p)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(contentFrame) }) { return }
        }
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let size = host.panel.frame.size
        host.panel.setFrameOrigin(NSPoint(x: v.maxX - size.width + margin - 16, y: v.maxY - size.height + margin - 16))
    }

    private func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(host.panel.frame.origin), forKey: Self.originKey)
    }

    // MARK: Drag

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private(set) var dragging = false

    func dragBegan() {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = host.panel.frame.origin
        dragging = false
    }

    /// Returns true once the pointer has moved far enough to count as a drag.
    @discardableResult
    func dragMoved() -> Bool {
        guard let m0 = dragStartMouse, let o0 = dragStartOrigin else { return false }
        let m = NSEvent.mouseLocation
        let dx = m.x - m0.x, dy = m.y - m0.y
        if !dragging, hypot(dx, dy) < 4 { return false }
        dragging = true
        host.panel.setFrameOrigin(NSPoint(x: o0.x + dx, y: o0.y + dy))
        return true
    }

    func dragEnded() {
        defer { dragStartMouse = nil; dragStartOrigin = nil; dragging = false }
        guard dragging else { return }
        snapToEdges()
        savePosition()
    }

    /// Snaps to the nearest screen edge when close; the index tab docks flush.
    private func snapToEdges() {
        let c = contentFrame
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(c) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let inset: CGFloat = themes.widgetShape == .indexTab ? 0 : 12
        var o = host.panel.frame.origin
        if c.minX - v.minX < snapDistance { o.x = v.minX + inset - margin }
        if v.maxX - c.maxX < snapDistance { o.x = v.maxX - inset - c.width - margin }
        if c.minY - v.minY < snapDistance { o.y = v.minY + inset - margin }
        if v.maxY - c.maxY < snapDistance { o.y = v.maxY - inset - c.height - margin }
        // Keep fully on screen.
        o.x = min(max(o.x, v.minX - margin), v.maxX - c.width - margin)
        o.y = min(max(o.y, v.minY - margin), v.maxY - c.height - margin)
        host.panel.animator().setFrameOrigin(o)
    }

    func showMenu(at point: NSPoint? = nil) {
        let menu = onMenu()
        let p = point ?? NSPoint(x: contentFrame.minX, y: contentFrame.minY)
        menu.popUp(positioning: nil, at: host.panel.convertPoint(fromScreen: p), in: host.panel.contentView)
    }
}

/// SwiftUI content of the widget window: the widget plus gestures.
struct WidgetRootView: View {
    let controller: WidgetController
    @Environment(AppModel.self) private var model
    @Environment(ThemeManager.self) private var themes
    @State private var pressedAt: Date?
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?
    @State private var dropTargeted = false

    var body: some View {
        ThemedRoot {
            WidgetView(state: model.widgetState, shape: themes.widgetShape, size: themes.widgetSize,
                       hotkeyHint: HotkeyManager.talkHint,
                       onStop: { model.stopSpeaking() },
                       onFix: { model.fixError() })
                .scaleEffect(dropTargeted ? 1.04 : 1)
                .opacity(model.widgetFullyOpaque || dropTargeted ? 1 : themes.idleOpacity)
                .animation(Motion.opacitySnap, value: model.widgetFullyOpaque)
                .contentShape(Rectangle())
                .onHover { model.setHovering($0) }
                .gesture(press)
                .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted, perform: handleDrop)
                .contextMenu { WidgetMenuItems() }
                .padding(WidgetMetrics.windowMargin)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in controller.sizeToFit() }
        }
    }

    /// Press-and-hold = talk, click = toggle panel, drag = move.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                if pressedAt == nil {
                    pressedAt = .now
                    controller.dragBegan()
                    holdTask = Task {
                        try? await Task.sleep(for: .milliseconds(280))
                        guard !Task.isCancelled, !controller.dragging else { return }
                        holding = true
                        model.talkPressed()
                    }
                } else if !holding, controller.dragMoved() {
                    holdTask?.cancel()
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                if holding {
                    model.talkReleased()
                } else if controller.dragging {
                    controller.dragEnded()
                } else {
                    model.togglePanel()
                }
                controller.dragEnded()
                holding = false
                pressedAt = nil
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.attach(urls: [url]) }
                }
            } else if p.canLoadObject(ofClass: NSImage.self) {
                _ = p.loadObject(ofClass: NSImage.self) { img, _ in
                    guard let img = img as? NSImage else { return }
                    Task { @MainActor in model.attach(image: img, name: "dropped.png"); model.showPanel() }
                }
            }
        }
        return true
    }
}

/// Right-click menu (also used by the status item via `MenuBuilder`).
struct WidgetMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        Button("Open panel") { model.showPanel() }
        Button("Tasks") { model.showTasks(nil) }
        Menu("Workflows") {
            ForEach(model.workflows.workflows) { w in
                Button(w.name) { model.runWorkflowFromUI(w.id) }
            }
        }
        Button("Attach screenshot") { model.attachScreenshot() }
        Divider()
        Picker("Shape", selection: Binding(get: { themes.widgetShape }, set: { themes.widgetShape = $0 })) {
            ForEach(WidgetShape.allCases) { Text($0.label).tag($0) }
        }
        Picker("Size", selection: Binding(get: { themes.widgetSize }, set: { themes.widgetSize = $0 })) {
            ForEach(WidgetSize.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Button("Settings…") { model.showSettings(nil) }
        Button("Quit Haku") { NSApp.terminate(nil) }
    }
}
