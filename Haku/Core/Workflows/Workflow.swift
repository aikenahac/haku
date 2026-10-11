import Foundation
import Observation

/// A saved command: trigger phrases → one action (Workflows editor mockup).
struct Workflow: Codable, Identifiable, Equatable, Sendable {
    enum Action: String, Codable, CaseIterable, Sendable, Identifiable {
        case askModel, shell, script, agent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .askModel: "Ask model"
            case .shell: "Shell"
            case .script: "Script"
            case .agent: "Agent"
            }
        }
    }

    var id = UUID()
    var name: String
    var phrases: [String]
    var matchSimilar = true
    var action: Action
    var agent: AgentKind = .claude
    var folder: String = "~"
    /// The prompt / command / script body, with `{after}` `{clipboard}` `{selection}` `{front app}` `{date}`.
    var template: String
    var confirmBeforeRunning = true
    var allowEditsWithoutAsking = false
    /// "Don't ask again for this workflow", set from a confirmation slip.
    var alwaysAllow = false
    var hasHotkey = false

    var primaryPhrase: String { phrases.first ?? name.lowercased() }

    /// The slug used to link from the panel ("deploy staging").
    var linkTitle: String { name.lowercased() }

    static let variables = ["{after}", "{clipboard}", "{selection}", "{front app}", "{date}"]

    /// Starter workflows so the panel row and editor aren't empty on first run.
    static let starters: [Workflow] = [
        Workflow(name: "Standup notes", phrases: ["morning notes", "standup"], action: .askModel,
                 template: "Turn this into three short standup bullets (yesterday, today, blockers): {after}\n\nClipboard for context:\n{clipboard}"),
        Workflow(name: "Summarize clipboard", phrases: ["sum this up", "summarize clipboard"], action: .askModel,
                 template: "Summarize this into five bullets:\n\n{clipboard}"),
        Workflow(name: "Tidy Downloads", phrases: ["clean up downloads", "tidy downloads"], action: .shell,
                 folder: "~/Downloads", template: "find ~/Downloads -name \"*.dmg\" -mtime +30 -delete"),
        Workflow(name: "Review my branch", phrases: ["review this branch", "review my branch"], action: .agent,
                 agent: .claude, folder: "~/haku", template: "Review the current branch against main and list concrete problems. {after}"),
    ]
}

@MainActor
@Observable
final class WorkflowStore {
    private(set) var workflows: [Workflow] = []
    @ObservationIgnored private let url: URL
    @ObservationIgnored var onChange: () -> Void = {}

    init(url: URL = AppPaths.workflows) {
        self.url = url
        if var saved = JSONFile.load([Workflow].self, from: url) {
            // Starter workflows that still point at the old default folder follow it to ~/haku.
            for i in saved.indices where saved[i].folder == "~/code" && Workflow.starters.contains(where: { $0.name == saved[i].name }) {
                saved[i].folder = "~/haku"
            }
            workflows = saved
            JSONFile.save(saved, to: url)
        } else {
            workflows = Workflow.starters
            save()
        }
    }

    func upsert(_ w: Workflow) {
        if let i = workflows.firstIndex(where: { $0.id == w.id }) { workflows[i] = w } else { workflows.append(w) }
        save()
    }

    func delete(_ id: UUID) {
        workflows.removeAll { $0.id == id }
        save()
    }

    func workflow(named name: String) -> Workflow? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return workflows.first { $0.name.lowercased() == n || $0.phrases.contains { $0.lowercased() == n } }
    }

    /// Exact trigger match at the start of an utterance. Returns the workflow and the `{after}` text.
    func match(_ utterance: String) -> (Workflow, String)? {
        let u = Self.normalize(utterance)
        var best: (Workflow, String, Int)?
        for w in workflows {
            for p in w.phrases {
                let phrase = Self.normalize(p)
                guard !phrase.isEmpty else { continue }
                if u == phrase || u.hasPrefix(phrase + " ") {
                    let after = String(u.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
                    let afterClean = after.hasPrefix("and ") ? String(after.dropFirst(4)) : after
                    if best == nil || phrase.count > best!.2 { best = (w, afterClean, phrase.count) }
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let kept = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private func save() {
        JSONFile.save(workflows, to: url)
        onChange()
    }
}
