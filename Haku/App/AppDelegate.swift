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
    private var tasksWindow: AppWindow?
    private var settingsWindow: AppWindow?
    private var workflowsWindow: AppWindow?
    private var onboardingWindow: AppWindow?
    private var settingsSection = SettingsSectionState()
    private var tasksSelection = TasksSelectionState()

    func applicationWillFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        themeManager.applyAppAppearance()
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
        if !settings.onboardingDone { showOnboarding() }

        Task {
            while true {
                await model.refreshModelStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for j in model.tasks.running { model.runner.cancel(j.id) }
        model.attachmentsStore.purgeAll()
    }

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

    func showTasks(select id: UUID?) {
        if let id { tasksSelection.selected = id }
        if tasksWindow == nil {
            tasksWindow = AppWindow(title: "Tasks", size: NSSize(width: 900, height: 620), minSize: NSSize(width: 680, height: 420)) {
                themed(TasksView(selection: tasksSelection))
            }
        }
        tasksWindow?.show()
    }

    func showSettings(_ section: String?) {
        if let section, let s = SettingsSection(rawValue: section) { settingsSection.section = s }
        if settingsWindow == nil {
            settingsWindow = AppWindow(title: "Settings", size: NSSize(width: 820, height: 640), minSize: NSSize(width: 700, height: 480)) {
                themed(SettingsView(state: settingsSection, showWorkflows: { [unowned self] in showWorkflows() },
                                    showOnboarding: { [unowned self] in showOnboarding() }))
            }
        }
        settingsWindow?.show()
    }

    func showWorkflows() {
        if workflowsWindow == nil {
            workflowsWindow = AppWindow(title: "Workflows", size: NSSize(width: 900, height: 640), minSize: NSSize(width: 720, height: 480)) {
                themed(WorkflowsView())
            }
        }
        workflowsWindow?.show()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = AppWindow(title: "Welcome to Haku", size: NSSize(width: 420, height: 560)) {
                themed(OnboardingView(onDone: { [unowned self] in
                    settings.onboardingDone = true
                    onboardingWindow?.window.close()
                    if settings.showWidget { widget.show() }
                }))
            }
        }
        onboardingWindow?.show()
    }
}

@Observable final class SettingsSectionState { var section: SettingsSection = .models }
@Observable final class TasksSelectionState { var selected: UUID? }
