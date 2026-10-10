import Foundation

/// The six widget states from HANDOFF › Floating widget.
enum WidgetState: Equatable, Sendable {
    case idle
    /// `level` is the live mic level 0…1; `elapsed` feeds the Typewriter timer.
    case listening(level: Double, elapsed: TimeInterval)
    case thinking
    case speaking
    /// Agent name, steps done/total, and how many jobs are running (stamp badge).
    case agentRunning(agent: String, done: Int, total: Int, jobs: Int)
    /// Short reason ("mic unavailable").
    case error(reason: String)

    /// Snaps idle opacity to 100%.
    var needsAttention: Bool {
        switch self {
        case .idle, .agentRunning: false
        case .listening, .thinking, .speaking, .error: true
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .idle: "Haku, idle"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case let .agentRunning(agent, done, total, jobs): "\(agent) running, step \(done) of \(total), \(jobs) jobs"
        case let .error(reason): "Error: \(reason)"
        }
    }

    /// Sample values used by previews and snapshot tests.
    static let samples: [(String, WidgetState)] = [
        ("i. idle", .idle),
        ("ii. listening", .listening(level: 1, elapsed: 4)),
        ("iii. thinking", .thinking),
        ("iv. speaking", .speaking),
        ("v. agent running", .agentRunning(agent: "Claude Code", done: 2, total: 5, jobs: 2)),
        ("vi. error", .error(reason: "mic unavailable")),
    ]
}
