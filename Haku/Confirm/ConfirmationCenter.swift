import Foundation
import Observation

/// What Haku wants to do and needs a yes for (tear-off slip).
struct ConfirmationRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        case shell(command: String, cwd: String?)
        case script(name: String, body: String, cwd: String?)
        case agent(prompt: String, agent: AgentKind, folder: String, edits: EditPermission)
        case applyEdits(jobTitle: String, agent: String, proposal: String)
    }

    let id = UUID()
    var kind: Kind
    /// Small-caps source line: "Shell command · workflow “Tidy Downloads”".
    var source: String
    /// Serif question: "Run this command?"
    var question: String
    var consequences: [CommandRisk.Consequence] = []
    /// Shown when the request came from a workflow/script that can be always-allowed.
    var alwaysAllowLabel: String?
    var workflowID: UUID?

    var voiceHint: String {
        if case .agent = kind { return "say “send it”" }
        return "say “yes” or “no”"
    }

    var approveLabel: String {
        switch kind {
        case .agent: "Send"
        case .applyEdits: "Apply"
        default: "Run"
        }
    }

    var denyLabel: String {
        switch kind {
        case .agent: "Not now"
        default: "Deny"
        }
    }
}

struct ConfirmationDecision: Equatable {
    var approved: Bool
    var alwaysAllow = false
    var agent: AgentKind?
    var folder: String?
    var edits: EditPermission?
}

/// Serializes confirmations: one slip at a time, callers await the decision.
@MainActor
@Observable
final class ConfirmationCenter {
    private(set) var current: ConfirmationRequest?
    /// Editable state of the current slip.
    var alwaysAllow = false
    var agent: AgentKind = .claude
    var folder: String = "~"
    var edits: EditPermission = .askFirst

    @ObservationIgnored private var continuation: CheckedContinuation<ConfirmationDecision, Never>?
    @ObservationIgnored private var queue: [(ConfirmationRequest, CheckedContinuation<ConfirmationDecision, Never>)] = []
    @ObservationIgnored var onPresent: (ConfirmationRequest) -> Void = { _ in }
    @ObservationIgnored var onDismiss: () -> Void = {}

    func ask(_ request: ConfirmationRequest) async -> ConfirmationDecision {
        await withCheckedContinuation { c in
            if current == nil { present(request, c) } else { queue.append((request, c)) }
        }
    }

    private func present(_ r: ConfirmationRequest, _ c: CheckedContinuation<ConfirmationDecision, Never>) {
        Log.info("confirm shown: \(r.source) — \(r.question)")
        current = r
        continuation = c
        alwaysAllow = false
        if case let .agent(_, a, f, e) = r.kind { agent = a; folder = f; edits = e }
        onPresent(r)
    }

    func approve(source: String = "click") { resolve(true, source: source) }
    func deny(source: String = "click") { resolve(false, source: source) }

    private func resolve(_ approved: Bool, source: String) {
        guard let r = current, let c = continuation else { return }
        Log.info("confirm \(approved ? "approved" : "denied") via \(source): \(r.source) — \(r.question)")
        var d = ConfirmationDecision(approved: approved, alwaysAllow: approved && alwaysAllow)
        if case .agent = r.kind { d.agent = agent; d.folder = folder; d.edits = edits }
        current = nil
        continuation = nil
        c.resume(returning: d)
        if !queue.isEmpty {
            let (next, nc) = queue.removeFirst()
            present(next, nc)
        } else {
            onDismiss()
        }
    }

    /// Interprets a spoken answer. Strict on purpose: the whole utterance must be a short yes/no phrase,
    /// so background talk ("okay so anyway…") never approves anything.
    @discardableResult
    func handleSpoken(_ text: String) -> Bool {
        switch Self.classify(text) {
        case .yes: approve(source: "voice “\(text)”"); return true
        case .no: deny(source: "voice “\(text)”"); return true
        case nil: return false
        }
    }

    enum SpokenAnswer { case yes, no }

    static let yesPhrases: Set<String> = ["yes", "yeah", "yep", "yes please", "do it", "run it", "send it", "go ahead",
                                          "approve", "apply", "apply it", "confirm", "ja", "da", "ja ja", "lahko", "izvedi", "pošlji", "posl ji", "poslji"]
    static let noPhrases: Set<String> = ["no", "nope", "no thanks", "don t", "dont", "stop", "cancel", "not now", "deny", "ne", "nee", "ne hvala"]

    static func classify(_ text: String) -> SpokenAnswer? {
        let t = WorkflowStore.normalize(text)
        guard !t.isEmpty, t.split(separator: " ").count <= 3 else { return nil }
        if noPhrases.contains(t) { return .no }
        if yesPhrases.contains(t) { return .yes }
        // "yes, go ahead" / "okay, send it": a lead-in word followed by a yes-phrase.
        let words = t.split(separator: " ").map(String.init)
        if words.count >= 2, ["yes", "yeah", "yep", "ok", "okay", "sure"].contains(words[0]),
           yesPhrases.contains(words.dropFirst().joined(separator: " ")) { return .yes }
        if words.count >= 2, words[0] == "no", noPhrases.contains(words.dropFirst().joined(separator: " ")) || words.count == 2 { return .no }
        return nil
    }
}
