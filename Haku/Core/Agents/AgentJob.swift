import Foundation
import Observation

/// A delegated job (Claude Code, Codex) or a local model job, as listed in the Tasks window.
struct AgentJob: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case queued, running, awaitingApproval, done, failed, cancelled
    }

    enum Runner: String, Codable, Sendable {
        case claude, codex, local
        var displayName: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .local: "Gemma · local"
            }
        }
        var agentKind: AgentKind? {
            switch self {
            case .claude: .claude
            case .codex: .codex
            case .local: nil
            }
        }
    }

    struct Step: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable { case todo, now, done }
        var text: String
        var state: State
    }

    struct LogLine: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case info, command, output, ok, fail, text }
        var date: Date
        var text: String
        var kind: Kind
    }

    var id = UUID()
    var runner: Runner
    var title: String
    var prompt: String
    var spokenAsk: String
    var directory: String?
    var permission: EditPermission
    var status: Status = .queued
    var started: Date = .now
    var ended: Date?
    var steps: [Step] = []
    var log: [LogLine] = []
    var summary: String?
    var changedFiles: [String] = []
    var approvals = 0
    var sessionID: String?
    var exitCode: Int32?
    var errorMessage: String?
    var attachmentPaths: [String] = []
    /// The conversation message that started this job (margin note alignment).
    var messageID: UUID?

    var isActive: Bool { status == .queued || status == .running }

    var stepProgress: (done: Int, total: Int) {
        let done = steps.filter { $0.state == .done }.count
        return (done, steps.count)
    }

    /// "running · step 3 of 5", "done · 14:31", "failed · exit 1 · retry?"
    var statusLine: String {
        switch status {
        case .queued: return "queued"
        case .running:
            let p = stepProgress
            return p.total > 0 ? "running · step \(min(p.done + 1, p.total)) of \(p.total)" : "running"
        case .awaitingApproval: return "waiting for your ok"
        case .done: return "done · \((ended ?? .now).formatted(date: .omitted, time: .shortened))"
        case .failed: return "failed\(exitCode.map { " · exit \($0)" } ?? "") · retry?"
        case .cancelled: return "cancelled"
        }
    }

    var durationText: String {
        let end = ended ?? .now
        let s = Int(end.timeIntervalSince(started))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \((s % 3600) / 60)m"
    }

    /// Latest short result for the margin ("41 passed, 3 failed").
    var marginDetail: String? {
        if let s = summary, status != .running { return s.split(separator: "\n").first.map(String.init) }
        return log.last(where: { $0.kind == .ok || $0.kind == .fail || $0.kind == .text })?.text
            .split(separator: "\n").first.map { String($0.prefix(60)) }
    }
}

@MainActor
@Observable
final class TaskStore {
    private(set) var jobs: [AgentJob] = []
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(url: URL = AppPaths.tasks) {
        self.url = url
        var loaded = JSONFile.load([AgentJob].self, from: url) ?? []
        // Anything still "running" from a previous launch was interrupted.
        for i in loaded.indices where loaded[i].isActive {
            loaded[i].status = .failed
            loaded[i].errorMessage = "Haku quit while this was running"
            loaded[i].ended = loaded[i].ended ?? .now
        }
        jobs = loaded
    }

    var running: [AgentJob] { jobs.filter(\.isActive) }

    func job(_ id: UUID) -> AgentJob? { jobs.first { $0.id == id } }

    func add(_ job: AgentJob) {
        jobs.insert(job, at: 0)
        scheduleSave()
    }

    func update(_ id: UUID, _ change: (inout AgentJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
        if jobs[i].log.count > 3000 { jobs[i].log.removeFirst(jobs[i].log.count - 3000) }
        scheduleSave()
    }

    func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearFinished() {
        jobs.removeAll { !$0.isActive && $0.status != .awaitingApproval }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            // Keep stored logs short; text history only.
            let trimmed = self.jobs.prefix(200).map { j -> AgentJob in
                var j = j
                if j.log.count > 300 { j.log = Array(j.log.suffix(300)) }
                return j
            }
            JSONFile.save(Array(trimmed), to: self.url)
        }
    }
}
