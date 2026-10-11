import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let themeManager = ThemeManager()
    private(set) var model: AppModel!
    private var widget: WidgetController!
    private var panel: PanelController!
    private var confirm: ConfirmController!
    private var statusItem: StatusItemController!
    private let hotkeys = HotkeyManager()
    private var mainWindow: AppWindow?
    private let nav = MainNavState()
    private var onboardingWindow: AppWindow?
    static weak var shared: AppDelegate?
    private var settingsSection = SettingsSectionState()
    private var tasksSelection = TasksSelectionState()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        HotkeyManager.migrateDefaults()   // before any view reads the shortcut
        NSApp.setActivationPolicy(.accessory)
    }

    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        themeManager.applyAppAppearance()
        guard !Self.isTestHost else { return }
        model = AppModel(settings: settings, themes: themeManager)

        widget = WidgetController(model: model, themes: themeManager)
        panel = PanelController(model: model, themes: themeManager)
        panel.widget = widget
        confirm = ConfirmController(model: model, themes: themeManager)
        confirm.widget = widget
        statusItem = StatusItemController(model: model)

        let menu: () -> NSMenu = { [unowned self] in
            MenuBuilder.menu(model: model, themes: themeManager,
                             togglePanel: { [unowned self] in panel.toggle() },
                             showWorkflows: { [unowned self] in showWorkflows() },
                             toggleWidget: { [unowned self] in toggleWidget() })
        }
        statusItem.onMenu = menu
        widget.onMenu = menu

        model.showPanel = { [unowned self] in if !panel.isVisible { panel.show() } }
        model.togglePanel = { [unowned self] in panel.toggle() }
        model.showTasks = { [unowned self] id in showTasks(select: id) }
        model.showSettings = { [unowned self] section in showSettings(section) }

        hotkeys.onTalkDown = { [unowned self] in model.talkPressed() }
        hotkeys.onTalkUp = { [unowned self] in model.talkReleased() }
        hotkeys.onOpenPanel = { [unowned self] in panel.toggle() }
        hotkeys.onShowTasks = { [unowned self] in showTasks(select: nil) }
        hotkeys.onWorkflow = { [unowned self] id in model.runWorkflowFromUI(id) }
        hotkeys.install()
        hotkeys.syncWorkflows(model.workflows.workflows)
        model.workflows.onChange = { [unowned self] in hotkeys.syncWorkflows(model.workflows.workflows) }

        trackFrontApp()
        Notifier.requestAuthorization()

        if settings.showWidget { widget.show() }
        applyDockPolicy()
        observeChanges { [unowned self] in _ = settings.showInDock; applyDockPolicy() }
        if !settings.onboardingDone { showOnboarding() } else if settings.showInDock { showMain() }

        // Wake word follows its setting, permissions, and whatever else is using the mic.
        observeChanges { [unowned self] in
            _ = (settings.wakeWordEnabled, settings.wakeSensitivity, settings.onboardingDone, settings.languages)
            model.syncWakeWord()
        }
        observeChanges { [unowned self] in model.updateWakePause() }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.syncWakeWord() }   // picks up a newly granted mic
        }

        Task { await model.brain.preload() }
        Task {
            while true {
                await model.refreshModelStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    /// Dock icon + menu bar when "Show in Dock" is on; otherwise a menu-bar/widget-only accessory app.
    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        // An LSUIElement app switched to .regular at runtime gets a placeholder Dock icon unless it sets one.
        if settings.showInDock {
            let icon = NSImage(named: "AppIcon")
            Log.info("dock icon \(icon == nil ? "missing" : "set") \(icon?.size ?? .zero)")
            if let icon { NSApp.applicationIconImage = icon }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let model else { return }
        for j in model.tasks.running { model.runner.cancel(j.id) }
        model.attachmentsStore.purgeAll()
    }

    /// haku://panel, haku://tasks, haku://settings, haku://ask?text=… (fills the input; never sends on its own).
    /// Debug builds also accept haku://send?text=… for end-to-end testing.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "haku" {
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value ?? ""
            switch url.host {
            case "panel": panel.show()
            case "main": showMain()
            case "tasks": showTasks(select: nil)
            case "settings": showSettings(text.isEmpty ? nil : text)
            case "workflows": showWorkflows()
            case "ask":
                model.draft = text
                panel.show()
            #if DEBUG
            case "send":
                panel.show()
                model.send(text, spoken: false)
            case "snapshot": snapshotWindows(to: text)
            case "approve": model.confirmations.approve(source: "url")
            case "deny": model.confirmations.deny(source: "url")
            case "state":
                let shapes: [String: WidgetShape] = ["slip": .slip, "tab": .indexTab, "seal": .seal]
                if let s = shapes[text] { themeManager.widgetShape = s }
                if let t = ThemeID(rawValue: text) { themeManager.select(t) }
            #endif
            default: break
            }
        }
    }

    #if DEBUG
    /// Renders every visible Haku window to PNGs (debug aid; needs no Screen Recording).
    private func snapshotWindows(to dir: String) {
        let out = URL(fileURLWithPath: dir.isEmpty ? NSTemporaryDirectory() : dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var manifest: [String] = []
        for (i, w) in NSApp.windows.enumerated() where w.isVisible {
            guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = "\(i)-\(w.title.isEmpty ? String(describing: type(of: w)) : w.title.replacingOccurrences(of: " ", with: "_")).png"
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
            manifest.append("\(name) \(NSStringFromRect(w.frame)) key=\(w.isKeyWindow)")
        }
        try? manifest.joined(separator: "\n").write(to: out.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    private func toggleWidget() {
        settings.showWidget.toggle()
        settings.showWidget ? widget.show() : widget.hide()
    }

    /// Remembers the last non-Haku app for `{front app}`.
    private func trackFrontApp() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier != Bundle.main.bundleIdentifier { ContextVariables.lastExternalApp = app?.localizedName }
        }
    }

    // MARK: Windows

    private func themed<V: View>(_ v: V) -> some View {
        ThemedRoot { v }
            .environment(model)
            .environment(themeManager)
            .environment(settings)
    }

    /// The main app window (chat history, tasks, workflows, settings).
    func showMain(_ section: MainSection? = nil) {
        if let section { nav.section = section }
        if mainWindow == nil {
            mainWindow = AppWindow(title: "Haku", size: NSSize(width: 1120, height: 740), minSize: NSSize(width: 860, height: 520),
                                   trafficLights: true) {
                themed(MainWindowView(nav: nav, tasksSelection: tasksSelection, settingsSection: settingsSection,
                                      showOnboarding: { [unowned self] in showOnboarding() }))
            }
        }
        mainWindow?.show()
    }

    func newChat() {
        model.newConversation()
        showMain(.chat)
    }

    func showTasks(select id: UUID?) {
        if let id { tasksSelection.selected = id }
        showMain(.tasks)
    }

    func showSettings(_ section: String?) {
        if let section, let s = SettingsSection(rawValue: section) { settingsSection.section = s }
        showMain(.settings)
    }

    func showWorkflows() { showMain(.workflows) }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = AppWindow(title: "Welcome to Haku", size: NSSize(width: 420, height: 560)) {
                themed(OnboardingView(onDone: { [unowned self] in
                    settings.onboardingDone = true
                    onboardingWindow?.window.close()
                    if settings.showWidget { widget.show() }
                    if settings.showInDock { showMain(.chat) }
                }))
            }
        }
        onboardingWindow?.show()
    }
}

@Observable final class SettingsSectionState { var section: SettingsSection = .models }
@Observable final class TasksSelectionState { var selected: UUID? }
