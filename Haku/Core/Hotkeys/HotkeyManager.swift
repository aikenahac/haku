import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Hold to talk (key-down starts, key-up sends).
    static let holdToTalk = Self("holdToTalk", default: .init(.space, modifiers: [.option]))
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

    func install() {
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

    /// Display string like "⌥ Space".
    static func display(_ name: KeyboardShortcuts.Name) -> String {
        guard let s = KeyboardShortcuts.getShortcut(for: name) else { return "—" }
        return s.description.map { String($0) }.joined(separator: " ").replacingOccurrences(of: "S p a c e", with: "Space")
    }

    /// Widget hint ("⌥ SPACE").
    static var talkHint: String { display(.holdToTalk).uppercased() }
}
