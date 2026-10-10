import Foundation

/// Parsed update from an agent's JSON event stream.
enum AgentEvent: Equatable, Sendable {
    case session(String)
    case log(String, AgentJob.LogLine.Kind)
    case steps([AgentJob.Step])
    case result(text: String, isError: Bool)
    case changedFile(String)
}

/// Claude Code `--output-format stream-json` parser.
enum ClaudeStreamParser {
    static func parse(_ line: String) -> [AgentEvent] {
        guard let json = JSONValue.parse(line) else {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? [] : [.log(t, .info)]
        }
        var out: [AgentEvent] = []
        switch json["type"]?.stringValue {
        case "system":
            if let s = json["session_id"]?.stringValue { out.append(.session(s)) }
        case "assistant":
            for block in json["message"]?["content"]?.arrayValue ?? [] {
                switch block["type"]?.stringValue {
                case "text":
                    if let t = block["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                        out.append(.log(t, .text))
                    }
                case "tool_use":
                    let name = block["name"]?.stringValue ?? "tool"
                    let input = block["input"]
                    if name == "TodoWrite", let todos = input?["todos"]?.arrayValue {
                        out.append(.steps(todos.map { t in
                            let status = t["status"]?.stringValue
                            return AgentJob.Step(text: t["content"]?.stringValue ?? "",
                                                 state: status == "completed" ? .done : status == "in_progress" ? .now : .todo)
                        }))
                    } else if name == "Bash", let cmd = input?["command"]?.stringValue {
                        out.append(.log("$ " + cmd, .command))
                    } else {
                        let target = input?["file_path"]?.stringValue ?? input?["path"]?.stringValue
                            ?? input?["pattern"]?.stringValue ?? input?["url"]?.stringValue ?? ""
                        let label = ["Read": "reading", "Edit": "editing", "Write": "writing", "MultiEdit": "editing",
                                     "Grep": "searching", "Glob": "listing"][name] ?? name.lowercased()
                        out.append(.log("\(label) \(target.abbreviatingHome)…".replacingOccurrences(of: "  ", with: " "), .info))
                        if ["Edit", "Write", "MultiEdit"].contains(name), !target.isEmpty { out.append(.changedFile(target)) }
                    }
                default: break
                }
            }
        case "user":
            for block in json["message"]?["content"]?.arrayValue ?? [] where block["type"]?.stringValue == "tool_result" {
                let isError = block["is_error"] == .bool(true)
                var text = block["content"]?.stringValue ?? ""
                if text.isEmpty, let parts = block["content"]?.arrayValue {
                    text = parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
                }
                for l in text.split(separator: "\n").suffix(12) {
                    let s = String(l)
                    out.append(.log(s, isError || s.contains("✗") || s.lowercased().contains("fail") ? .fail
                                    : s.contains("✓") || s.lowercased().contains("pass") ? .ok : .output))
                }
            }
        case "result":
            let isError = json["is_error"] == .bool(true) || json["subtype"]?.stringValue != "success"
            out.append(.result(text: json["result"]?.stringValue ?? "", isError: isError))
            if let s = json["session_id"]?.stringValue { out.append(.session(s)) }
        default: break
        }
        return out
    }
}

/// Codex `exec --json` parser.
enum CodexStreamParser {
    static func parse(_ line: String) -> [AgentEvent] {
        guard let json = JSONValue.parse(line) else {
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? [] : [.log(t, .info)]
        }
        var out: [AgentEvent] = []
        let type = json["type"]?.stringValue ?? ""
        switch type {
        case "thread.started":
            if let id = json["thread_id"]?.stringValue { out.append(.session(id)) }
        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] else { break }
            let done = type == "item.completed"
            switch item["type"]?.stringValue {
            case "command_execution":
                if type == "item.started", let cmd = item["command"]?.stringValue { out.append(.log("$ " + cmd, .command)) }
                if done {
                    let output = item["aggregated_output"]?.stringValue ?? ""
                    let failed = (item["exit_code"]?.stringValue).map { $0 != "0" } ?? false
                    for l in output.split(separator: "\n").suffix(12) { out.append(.log(String(l), failed ? .fail : .output)) }
                }
            case "agent_message":
                if done, let t = item["text"]?.stringValue {
                    out.append(.log(t, .text))
                    out.append(.result(text: t, isError: false))
                }
            case "todo_list":
                let items = item["items"]?.arrayValue ?? []
                var steps = items.map { AgentJob.Step(text: $0["text"]?.stringValue ?? "", state: $0["completed"] == .bool(true) ? .done : .todo) }
                if let i = steps.firstIndex(where: { $0.state == .todo }) { steps[i].state = .now }
                out.append(.steps(steps))
            case "file_change":
                for c in item["changes"]?.arrayValue ?? [] {
                    if let p = c["path"]?.stringValue { out.append(.changedFile(p)); out.append(.log("editing \(p.abbreviatingHome)", .info)) }
                }
            default: break
            }
        case "turn.failed", "error":
            let msg = json["error"]?["message"]?.stringValue ?? json["message"]?.stringValue ?? "failed"
            out.append(.log(msg, .fail))
            out.append(.result(text: msg, isError: true))
        default: break
        }
        return out
    }
}

/// Spawns `claude -p` / `codex exec`, streams their JSON into the TaskStore.
@MainActor
final class AgentRunner {
    private let store: TaskStore
    private let settings: AppSettings
    private var processes: [UUID: Process] = [:]
    private var gitBaseline: [UUID: Set<String>] = [:]
    private var lastResult: [UUID: (String, Bool)] = [:]
    var onFinish: (AgentJob) -> Void = { _ in }

    init(store: TaskStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var runningCount: Int { processes.count }

    static let readOnlyRules = "Do not create, edit or delete files. Shell commands must not modify the project."
    static let askFirstRules = "Do not create, edit or delete files yet. If changes are needed, finish with a section titled 'Proposed changes:' that lists exactly what you would change. The user will approve before anything is edited."

    func arguments(for job: AgentJob, resume: Bool = false) -> [String] {
        var prompt = job.prompt
        if !job.attachmentPaths.isEmpty {
            prompt += "\n\nAttached files (context only — read them if relevant):\n" + job.attachmentPaths.map { "- \($0)" }.joined(separator: "\n")
        }
        switch job.runner {
        case .claude:
            if resume, let s = job.sessionID {
                return ["-p", "The user approved. Apply the proposed changes now, then summarize what changed.",
                        "--resume", s, "--output-format", "stream-json", "--verbose",
                        "--permission-mode", "acceptEdits", "--allowedTools", "Bash Read Grep Glob Edit Write MultiEdit TodoWrite"]
            }
            var a = ["-p", prompt, "--output-format", "stream-json", "--verbose"]
            switch job.permission {
            case .readOnly, .askFirst:
                a += ["--permission-mode", "default",
                      "--allowedTools", "Bash Read Grep Glob WebFetch WebSearch TodoWrite",
                      "--disallowedTools", "Edit Write MultiEdit NotebookEdit",
                      "--append-system-prompt", job.permission == .readOnly ? Self.readOnlyRules : Self.askFirstRules]
            case .allowed:
                a += ["--permission-mode", "acceptEdits", "--allowedTools", "Bash Read Grep Glob Edit Write MultiEdit WebFetch TodoWrite"]
            }
            return a
        case .codex:
            let dir = (job.directory ?? "~").expandingTilde
            let sandbox = (resume || job.permission == .allowed) ? "workspace-write" : "read-only"
            let text = resume
                ? "The user approved these proposed changes. Apply them now, then summarize what changed.\n\n\(job.summary ?? "")\n\nOriginal task: \(prompt)"
                : job.permission == .askFirst ? "\(prompt)\n\n\(Self.askFirstRules)" : prompt
            return ["exec", "--json", "--skip-git-repo-check", "-C", dir, "--sandbox", sandbox, text]
        case .local:
            return []
        }
    }

    func binaryPath(for kind: AgentKind) -> String? {
        let configured = settings.agent(kind).binaryPath
        return ShellRunner.which(configured.isEmpty ? kind.defaultBinary : configured)
    }

    func start(_ id: UUID, resume: Bool = false) {
        guard let job = store.job(id), let kind = job.runner.agentKind else { return }
        guard let bin = binaryPath(for: kind) else {
            fail(id, "\(kind.displayName) isn't installed (set its path in Settings › Models & agents)")
            return
        }
        let dir = (job.directory ?? settings.defaultFolder).expandingTilde
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            fail(id, "Folder \(dir.abbreviatingHome) doesn't exist")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = arguments(for: job, resume: resume)
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        p.environment = ShellRunner.loginEnvironment
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let parse: @Sendable (String) -> [AgentEvent] = kind == .claude ? ClaudeStreamParser.parse : CodexStreamParser.parse
        let lines = LineSplitter()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let events = lines.feed(data).flatMap(parse)
            Task { @MainActor in self?.apply(events, to: id) }
        }
        let errLines = LineSplitter()
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let ls = errLines.feed(data)
            Task { @MainActor in self?.apply(ls.map { .log($0, .info) }, to: id) }
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let rest = lines.flush().flatMap(parse)
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in
                self?.apply(rest, to: id)
                self?.finished(id, status: status, interrupted: reason == .uncaughtSignal)
            }
        }

        store.update(id) {
            $0.status = .running
            if !resume { $0.started = .now }
            $0.ended = nil
            $0.errorMessage = nil
            if resume { $0.approvals += 1 }
            $0.log.append(.init(date: .now, text: resume ? "applying approved changes…" : "started in \(dir.abbreviatingHome)", kind: .info))
        }
        processes[id] = p
        Task {
            // Baseline first, so files the agent touches show up as changed.
            if self.gitBaseline[id] == nil { self.gitBaseline[id] = await Self.gitStatus(dir) }
            guard self.store.job(id)?.status == .running else { self.processes[id] = nil; return }
            do {
                try p.run()
            } catch {
                self.processes[id] = nil
                self.fail(id, "Couldn't start \(kind.displayName): \(error.localizedDescription)")
            }
        }
    }

    func cancel(_ id: UUID) {
        guard let p = processes[id] else {
            store.update(id) { if $0.isActive { $0.status = .cancelled; $0.ended = .now } }
            return
        }
        store.update(id) { $0.status = .cancelled; $0.log.append(.init(date: .now, text: "cancelling…", kind: .info)) }
        guard p.isRunning else { processes[id] = nil; store.update(id) { $0.ended = .now }; return }
        p.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }
    }

    private func apply(_ events: [AgentEvent], to id: UUID) {
        guard !events.isEmpty else { return }
        store.update(id) { job in
            for e in events {
                switch e {
                case .session(let s): job.sessionID = s
                case .log(let text, let kind): job.log.append(.init(date: .now, text: text, kind: kind))
                case .steps(let s): job.steps = s
                case .result(let text, let isError):
                    job.summary = text
                    lastResult[id] = (text, isError)
                case .changedFile(let f):
                    let rel = f.hasPrefix((job.directory ?? "").expandingTilde + "/") ? String(f.dropFirst((job.directory ?? "").expandingTilde.count + 1)) : f.abbreviatingHome
                    if !job.changedFiles.contains(where: { $0.hasSuffix(rel) }) { job.changedFiles.append("M \(rel)") }
                }
            }
        }
    }

    private func finished(_ id: UUID, status: Int32, interrupted: Bool) {
        processes[id] = nil
        guard let job = store.job(id) else { return }
        let dir = (job.directory ?? settings.defaultFolder).expandingTilde
        Task {
            let after = await Self.gitStatus(dir)
            let before = self.gitBaseline[id] ?? []
            let changed = after.subtracting(before).sorted()
            self.store.update(id) { j in
                if !changed.isEmpty { j.changedFiles = changed }
                j.ended = .now
                j.exitCode = status
                if j.status == .cancelled { return }
                let (_, isError) = self.lastResult[id] ?? ("", status != 0)
                if status != 0 || isError {
                    j.status = .failed
                    j.errorMessage = j.errorMessage ?? (j.summary?.isEmpty == false ? j.summary : "exit \(status)")
                } else if j.permission == .askFirst && (j.summary ?? "").localizedCaseInsensitiveContains("proposed changes") && j.approvals == 0 {
                    j.status = .awaitingApproval
                } else {
                    j.status = .done
                }
                j.steps = j.steps.map { s in var s = s; if j.status == .done { s.state = .done }; return s }
            }
            if let final = self.store.job(id), !final.isActive {
                if final.status != .awaitingApproval { self.gitBaseline[id] = nil }
                self.onFinish(final)
            }
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        store.update(id) {
            $0.status = .failed
            $0.ended = .now
            $0.errorMessage = message
            $0.log.append(.init(date: .now, text: message, kind: .fail))
        }
        if let j = store.job(id) { onFinish(j) }
    }

    /// `git status --porcelain` lines ("M path") or empty when not a repo.
    static func gitStatus(_ dir: String) async -> Set<String> {
        let r = await ShellRunner.runProcess("/usr/bin/git", ["-C", dir, "status", "--porcelain"], timeout: 10)
        guard r.exitCode == 0 else { return [] }
        return Set(r.output.split(separator: "\n").map { line in
            let s = String(line)
            let code = s.prefix(2).trimmingCharacters(in: .whitespaces)
            return "\(code == "??" ? "A" : code.prefix(1)) \(s.dropFirst(3))"
        })
    }
}

/// Splits a byte stream into lines across reads.
final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func feed(_ data: Data) -> [String] {
        lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let nl = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...nl)
            }
            return lines
        }
    }

    func flush() -> [String] {
        lock.withLock {
            defer { buffer.removeAll() }
            let s = String(decoding: buffer, as: UTF8.self)
            return s.isEmpty ? [] : [s]
        }
    }
}
