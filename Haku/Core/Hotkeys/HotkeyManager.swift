import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to talk (key-down starts, key-up sends).
    static let holdToTalk = Self("holdToTalk", default: .init(.space, modifiers: [.control, .option]))
    static let openPanel = Self("openPanel", default: .init(.space, modifiers: [.option, .shift]))
    static let showTasks = Self("showTasks", default: .init(.t, modifiers: [.option, .shift]))

    static func workflow(_ id: UUID) -> Self { Self("workflow-\(id.uuidString)") }
}

/// Global hotkeys (Carbon via KeyboardShortcuts, so no Accessibility needed for these).
@MainActor
final class HotkeyManager {
    var onTalkDown: () -> Void = {}
    var onTalkUp: () -> Void = {}
    var onOpenPanel: () -> Void = {}
    var onShowTasks: () -> Void = {}
    var onWorkflow: (UUID) -> Void = { _ in }
    private var registeredWorkflows: Set<UUID> = []

    /// One-time move off the old ⌥Space default (it clashed with other launchers); custom choices are kept.
    static func migrateDefaults() {
        let key = "hotkeys.migrated.v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if KeyboardShortcuts.getShortcut(for: .holdToTalk) == .init(.space, modifiers: [.option]) {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.control, .option]), for: .holdToTalk)
        }
    }

    func install() {
        Self.migrateDefaults()
        KeyboardShortcuts.onKeyDown(for: .holdToTalk) { [weak self] in self?.onTalkDown() }
        KeyboardShortcuts.onKeyUp(for: .holdToTalk) { [weak self] in self?.onTalkUp() }
        KeyboardShortcuts.onKeyDown(for: .openPanel) { [weak self] in self?.onOpenPanel() }
        KeyboardShortcuts.onKeyDown(for: .showTasks) { [weak self] in self?.onShowTasks() }
    }

    func syncWorkflows(_ workflows: [Workflow]) {
        for w in workflows where w.hasHotkey && !registeredWorkflows.contains(w.id) {
            registeredWorkflows.insert(w.id)
            let id = w.id
            KeyboardShortcuts.onKeyDown(for: .workflow(id)) { [weak self] in self?.onWorkflow(id) }
        }
    }

    /// Display string like "⌃⌥ Space".
    static func display(_ name: KeyboardShortcuts.Name) -> String {
        let p = parts(name)
        return p.dropLast().joined() + " " + (p.last ?? "")
    }

    /// ["⌃", "⌥", "Space"], or the default when unset.
    static func parts(_ name: KeyboardShortcuts.Name) -> [String] {
        guard let s = KeyboardShortcuts.getShortcut(for: name) else { return name == .holdToTalk ? ThemeCopy.defaultKeys : ["—"] }
        var out: [String] = []
        let m = s.modifiers
        if m.contains(.control) { out.append("⌃") }
        if m.contains(.option) { out.append("⌥") }
        if m.contains(.shift) { out.append("⇧") }
        if m.contains(.command) { out.append("⌘") }
        let key = s.description.drop { "⌃⌥⇧⌘".contains($0) }
        out.append(key.isEmpty ? "?" : String(key))
        return out
    }

    static var talkKeys: [String] { parts(.holdToTalk) }
}
