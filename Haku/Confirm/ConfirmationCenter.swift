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
        current = r
        continuation = c
        alwaysAllow = false
        if case let .agent(_, a, f, e) = r.kind { agent = a; folder = f; edits = e }
        onPresent(r)
    }

    func approve() { resolve(true) }
    func deny() { resolve(false) }

    private func resolve(_ approved: Bool) {
        guard let r = current, let c = continuation else { return }
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

    /// Interprets a spoken answer. Returns true when it was a decision.
    @discardableResult
    func handleSpoken(_ text: String) -> Bool {
        let t = WorkflowStore.normalize(text)
        let yes = ["yes", "yeah", "yep", "sure", "ok", "okay", "do it", "run it", "send it", "go ahead", "approve", "ja", "da", "lahko"]
        let no = ["no", "nope", "don t", "dont", "stop", "cancel", "not now", "deny", "ne"]
        let words = Set(t.split(separator: " ").map(String.init))
        if no.contains(where: { t == $0 || t.hasPrefix($0 + " ") || words.contains($0) }) { deny(); return true }
        if yes.contains(where: { t == $0 || t.hasPrefix($0 + " ") || t.hasSuffix(" " + $0) || words.contains($0) }) { approve(); return true }
        return false
    }
}
