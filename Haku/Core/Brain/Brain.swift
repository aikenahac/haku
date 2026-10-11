import AppKit
import Foundation

/// What the Brain needs from the app to act: confirmations, delegation, workflows.
@MainActor
protocol BrainHost: AnyObject {
    func confirm(_ request: ConfirmationRequest) async -> ConfirmationDecision
    func delegate(agent: AgentKind?, task: String, directory: String?, spokenAsk: String,
                  attachments: [Attachment], messageID: UUID) async -> DelegationOutcome
    func runWorkflow(named: String, after: String, messageID: UUID) async -> String
    /// Excerpts from earlier chats matching `query` (plain text for the model).
    func searchHistory(_ query: String) -> String
    var workflowList: [Workflow] { get }
}

enum DelegationOutcome {
    case started(AgentJob)
    case declined
    case failed(String)
}

/// One turn's result.
struct BrainReply {
    var text: String
    var startedJob: AgentJob?
    var usedEscalation = false
}

/// Gemma with tools: decides to answer, run a tool, escalate to the big model, or dispatch an agent.
@MainActor
final class Brain {
    private let settings: AppSettings
    weak var host: BrainHost?
    private var context: [LLMMessage] = []
    private let maxContext = 16
    private let maxToolRounds = 5

    let models: ModelManager

    init(settings: AppSettings) {
        self.settings = settings
        models = ModelManager(config: Self.config(settings))
    }

    var client: OpenAIClient { OpenAIClient(endpoint: settings.endpoint, apiKey: settings.apiKey) }

    static func config(_ s: AppSettings) -> ModelManager.Config {
        .init(endpoint: s.endpoint, apiKey: s.apiKey, serverType: s.serverType, lmsPath: s.lmsPath)
    }

    /// Escalation model unloads itself after 10 idle minutes.
    static let escalationTTL = 600

    /// Server key for the routing model, loading it if needed.
    func routingKey(status: (String) -> Void = { _ in }) async throws -> String {
        await models.update(Self.config(settings))
        let cached = await models.key(for: settings.routingModel)
        if cached != settings.routingModel { return try await models.ensureLoaded(settings.routingModel) }
        status("loading \(settings.routingModel)")
        return try await models.ensureLoaded(settings.routingModel)
    }

    func escalationKey() async throws -> String {
        await models.update(Self.config(settings))
        return try await models.ensureLoaded(settings.escalationModel, ttl: Self.escalationTTL)
    }

    /// Loads the always-on routing model at launch.
    func preload() async {
        do { let k = try await routingKey(); Log.info("routing model ready: \(k)") }
        catch { Log.info("routing model not ready: \(error.localizedDescription)") }
    }

    /// True for "no models loaded" / "model not found" style errors worth one load-and-retry.
    nonisolated static func isNotLoaded(_ e: Error) -> Bool {
        guard case let LLMError.http(code, body)? = e as? LLMError else { return false }
        let b = body.lowercased()
        return (code == 400 || code == 404) && (b.contains("no models loaded") || b.contains("not loaded") || b.contains("model_not_found") || b.contains("not found"))
    }

    func reset() { context = [] }

    /// Seeds context from saved history (text only).
    func seed(_ messages: [ChatMessage]) {
        context = messages.suffix(maxContext).map { $0.role == .user ? .user($0.plainText) : .assistant($0.plainText) }
    }

    // MARK: Turn

    func respond(to text: String, attachments: [Attachment], messageID: UUID,
                 onDelta: @escaping (String) -> Void, onStatus: @escaping (String) -> Void = { _ in }) async throws -> BrainReply {
        var userContent = text
        if !attachments.isEmpty {
            userContent += "\n\n[Attached as context — paths only, you can't see them: "
                + attachments.compactMap { $0.url?.path }.joined(separator: ", ") + "]"
        }
        var turn: [LLMMessage] = [.user(userContent)]
        var reply = BrainReply(text: "")
        var streamed = ""

        var model = try await routingKey(status: onStatus)
        onStatus("")
        var retried = false
        var round = 0
        while round < maxToolRounds {
            var calls: [LLMToolCall] = []
            var content = ""
            let stream = client.streamChat(model: model,
                                           messages: [.system(systemPrompt())] + context + turn,
                                           tools: round < maxToolRounds - 1 ? Self.tools(settings: settings) : nil)
            do {
                for try await ev in stream {
                    switch ev {
                    case .content(let s):
                        content += s
                        streamed += s
                        onDelta(streamed)
                    case .toolCalls(let c): calls = c
                    case .done: break
                    }
                }
            } catch let e as LLMError {
                if Self.isNotLoaded(e), !retried, content.isEmpty {
                    retried = true
                    onStatus("loading \(settings.routingModel)")
                    await models.update(Self.config(settings))
                    model = try await models.ensureLoaded(settings.routingModel)
                    onStatus("")
                    continue
                }
                if case .unreachable = e, settings.fallback == .useEscalation, round == 0 {
                    let r = try await escalate(text, onDelta: onDelta)
                    return remember(text, BrainReply(text: r, usedEscalation: true))
                }
                throw e
            }

            if calls.isEmpty {
                reply.text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }

            turn.append(.assistant(content.isEmpty ? nil : content, tools: calls))
            var terminal: String?
            for call in calls {
                let args = call.args
                switch call.function.name {
                case "answer":
                    terminal = args["text"]?.stringValue ?? content
                case "escalate":
                    onStatus("thinking harder")
                    let prompt = args["prompt"]?.stringValue ?? text
                    streamed = ""
                    terminal = try await escalate(prompt, onDelta: onDelta)
                    reply.usedEscalation = true
                case "delegate_agent":
                    let agent = args["agent"]?.stringValue.flatMap(AgentKind.init(rawValue:))
                    let task = args["task"]?.stringValue ?? text
                    let dir = args["dir"]?.stringValue
                    let outcome = await host?.delegate(agent: agent, task: task, directory: dir, spokenAsk: text,
                                                       attachments: attachments, messageID: messageID) ?? .failed("no host")
                    switch outcome {
                    case .started(let job):
                        reply.startedJob = job
                        let where_ = job.directory.map { " in `\($0.abbreviatingHome)`" } ?? ""
                        terminal = "Handed to \(job.runner.displayName)\(where_). I'll note it in the margin when it's done."
                    case .declined:
                        terminal = "Okay, not sending it."
                    case .failed(let why):
                        terminal = "Couldn't start that: \(why)"
                    }
                default:
                    if call.function.name == "search_history" { onStatus("checking earlier chats") }
                    let result = await execute(call.function.name, args, messageID: messageID)
                    if call.function.name == "search_history" { onStatus("") }
                    turn.append(.tool(call.id, name: call.function.name, result))
                }
                if terminal != nil { break }
            }
            if let terminal {
                reply.text = terminal
                onDelta(terminal)
                break
            }
            // Fill in tool results for any calls skipped above (keeps the transcript valid).
            for call in calls where !turn.contains(where: { $0.tool_call_id == call.id }) {
                turn.append(.tool(call.id, name: call.function.name, "skipped"))
            }
            streamed = ""
            round += 1
        }
        if reply.text.isEmpty { reply.text = "Done." ; onDelta(reply.text) }
        return remember(text, reply)
    }

    private func remember(_ user: String, _ reply: BrainReply) -> BrainReply {
        context.append(.user(user))
        context.append(.assistant(reply.text))
        if context.count > maxContext { context.removeFirst(context.count - maxContext) }
        return reply
    }

    /// The bigger model, loaded on demand by the server. Streams straight into the reply.
    func escalate(_ prompt: String, onDelta: @escaping (String) -> Void) async throws -> String {
        var out = ""
        let messages: [LLMMessage] = [.system(Self.escalationPrompt)] + context.suffix(8) + [.user(prompt)]
        let model = try await escalationKey()
        for try await ev in client.streamChat(model: model, messages: messages, temperature: 0.5) {
            if case .content(let s) = ev { out += s; onDelta(out) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turns a finished agent result into one spoken sentence.
    func spokenSummary(of job: AgentJob) async -> String {
        let raw = job.summary ?? job.errorMessage ?? ""
        let fallback = job.status == .failed ? "\(job.runner.displayName) failed: \(job.title)." : "\(job.runner.displayName) finished \(job.title)."
        guard !raw.isEmpty else { return fallback }
        let prompt = "Summarize this agent result in one short spoken sentence (max 25 words), no markdown:\n\n\(raw.prefix(4000))"
        guard let model = try? await routingKey() else { return fallback }
        let s = try? await client.complete(model: model, messages: [.user(prompt)], maxTokens: 80)
        return (s?.isEmpty == false ? s! : fallback)
    }

    /// Short title for a job from its prompt ("Run devenv tests, report failures").
    func title(for task: String) async -> String {
        let prompt = "Write a 3–7 word title for this task, imperative, no quotes or trailing period:\n\n\(task.prefix(1500))"
        guard let model = try? await routingKey() else { return String(task.prefix(60)) }
        let t = (try? await client.complete(model: model, messages: [.user(prompt)], maxTokens: 24)) ?? ""
        let clean = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'. \n"))
        return clean.isEmpty || clean.count > 80 ? String(task.prefix(60)) : clean
    }

    // MARK: Tools

    static func tools(settings: AppSettings) -> [LLMTool] {
        var agents: [String] = []
        if settings.claude.enabled { agents.append("claude") }
        if settings.codex.enabled { agents.append("codex") }
        var tools: [LLMTool] = [
            LLMTool("answer", "Reply to the user directly. Use for questions, chat and anything you can answer yourself.",
                    properties: ["text": LLMTool.prop("string", "The reply. Short, plain, voice-friendly.")], required: ["text"]),
            LLMTool("open_app", "Open or switch to a macOS app by name.",
                    properties: ["name": LLMTool.prop("string", "App name, e.g. Safari, Xcode, Notes")], required: ["name"]),
            LLMTool("open_url", "Open a URL in the default browser.",
                    properties: ["url": LLMTool.prop("string", "Full URL including https://")], required: ["url"]),
            LLMTool("run_shortcut", "Run an Apple Shortcut by its exact name.",
                    properties: ["name": LLMTool.prop("string", "Shortcut name"),
                                 "input": LLMTool.prop("string", "Optional text input")], required: ["name"]),
            LLMTool("run_applescript", "Run an AppleScript. The user must approve it first.",
                    properties: ["script": LLMTool.prop("string", "AppleScript source")], required: ["script"]),
            LLMTool("run_shell", "Run a shell command (zsh). The user must approve it first. Prefer small, safe commands.",
                    properties: ["cmd": LLMTool.prop("string", "The command"),
                                 "dir": LLMTool.prop("string", "Working directory, e.g. ~/code/app")], required: ["cmd"]),
            LLMTool("escalate", "Hand a hard question (deep reasoning, long writing, tricky code explanation) to the larger local model.",
                    properties: ["prompt": LLMTool.prop("string", "The full, self-contained question")], required: ["prompt"]),
            LLMTool("run_workflow", "Run one of the user's saved workflows.",
                    properties: ["name": LLMTool.prop("string", "Workflow name"),
                                 "after": LLMTool.prop("string", "Anything the user said after the trigger phrase")], required: ["name"]),
            LLMTool("list_shortcuts", "List the user's Apple Shortcuts.", properties: [:], required: []),
            LLMTool("search_history", "Search the user's earlier chats when they refer to something said before (\"that script from yesterday\", \"what did you say about…\"). Returns matching excerpts.",
                    properties: ["query": LLMTool.prop("string", "Key words to look for, e.g. \"backup script rsync\"")], required: ["query"]),
        ]
        if !agents.isEmpty {
            tools.append(LLMTool("delegate_agent",
                                 "Hand coding or repo work (run tests, fix bugs, edit code, review a branch, investigate a project) to a coding agent. Write `task` as a clean, self-contained instruction for the agent, not a copy of the user's words.",
                                 properties: ["agent": LLMTool.prop("string", "Which agent", enum: agents),
                                              "task": LLMTool.prop("string", "Clear task prompt for the agent"),
                                              "dir": LLMTool.prop("string", "Project folder, e.g. ~/code/devenv")],
                                 required: ["task"]))
        }
        return tools
    }

    private func execute(_ name: String, _ args: JSONValue, messageID: UUID) async -> String {
        switch name {
        case "open_app":
            let app = args["name"]?.stringValue ?? ""
            return await Self.openApp(app)
        case "open_url":
            guard let s = args["url"]?.stringValue, let url = URL(string: s.contains("://") ? s : "https://\(s)") else { return "bad url" }
            NSWorkspace.shared.open(url)
            return "opened \(url.absoluteString)"
        case "run_shortcut":
            let n = args["name"]?.stringValue ?? ""
            let input = args["input"]?.stringValue
            let r = await ShellRunner.runProcess("/usr/bin/shortcuts", ["run", n] + (input == nil ? [] : ["--input-path", "-"]),
                                                 stdin: input, timeout: 120)
            return r.exitCode == 0 ? "ran shortcut \(n). \(r.output.prefix(800))" : "shortcut failed: \(r.output.prefix(400))"
        case "list_shortcuts":
            let r = await ShellRunner.runProcess("/usr/bin/shortcuts", ["list"], timeout: 15)
            return String(r.output.prefix(2000))
        case "run_applescript":
            let script = args["script"]?.stringValue ?? ""
            let d = await host?.confirm(ConfirmationRequest(kind: .script(name: "AppleScript", body: script, cwd: nil),
                                                            source: "AppleScript", question: "Run this script?"))
            guard d?.approved == true else { return "the user declined" }
            let r = await ShellRunner.runProcess("/usr/bin/osascript", ["-e", script], timeout: 60)
            return r.summary
        case "run_shell":
            let cmd = args["cmd"]?.stringValue ?? ""
            let dir = args["dir"]?.stringValue
            let consequences = await CommandRisk.assess(cmd, cwd: dir)
            let d = await host?.confirm(ConfirmationRequest(kind: .shell(command: cmd, cwd: dir), source: "Shell command",
                                                            question: "Run this command?", consequences: consequences))
            guard d?.approved == true else { return "the user declined" }
            return await ShellRunner.run(cmd, cwd: dir).summary
        case "search_history":
            return host?.searchHistory(args["query"]?.stringValue ?? "") ?? "no host"
        case "run_workflow":
            let n = args["name"]?.stringValue ?? ""
            return await host?.runWorkflow(named: n, after: args["after"]?.stringValue ?? "", messageID: messageID) ?? "no host"
        default:
            return "unknown tool \(name)"
        }
    }

    static func openApp(_ name: String) async -> String {
        let ws = NSWorkspace.shared
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                    "~/Applications".expandingTilde]
        let lower = name.lowercased().replacingOccurrences(of: ".app", with: "")
        for d in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: d) else { continue }
            if let hit = items.first(where: { $0.lowercased() == lower + ".app" })
                ?? items.first(where: { $0.lowercased().hasPrefix(lower) && $0.hasSuffix(".app") }) {
                let url = URL(fileURLWithPath: d).appendingPathComponent(hit)
                _ = try? await ws.openApplication(at: url, configuration: .init())
                return "opened \(hit.replacingOccurrences(of: ".app", with: ""))"
            }
        }
        return "couldn't find an app called \(name)"
    }

    // MARK: Prompts

    private func systemPrompt() -> String {
        let flows = (host?.workflowList ?? []).map { "- \($0.name): says \"\($0.phrases.joined(separator: "\" / \""))\" → \($0.action.label)" }
            .joined(separator: "\n")
        return """
        You are Haku, a small voice assistant living in a corner of the user's Mac. You take quick jobs yourself and hand coding work to agents.
        Today is \(Date.now.formatted(date: .complete, time: .shortened)). Default project folder: \(settings.defaultFolder).

        How to act:
        - Questions and chat: reply directly (or call `answer`). One to three short sentences, plain words, no lists unless asked. Replies may be spoken aloud.
        - Opening apps/sites, running shortcuts: use the tools.
        - Anything about a code project (tests, bugs, edits, reviews, builds): call `delegate_agent` with a clean task prompt and the folder. Don't ask follow-up questions if you can infer the folder; use the default folder otherwise.
        - Hard reasoning or long writing: call `escalate`.
        - Shell/AppleScript only when nothing else fits; the user approves each one.
        - When the user's words match a saved workflow, call `run_workflow`.
        - Each voice command starts a fresh chat. If the user refers to something earlier that isn't in this chat, call `search_history` first.
        Formatting: wrap file paths in backticks. You may highlight the single most important phrase with ==double equals==. No other markdown.
        Attachments are files you can't see; pass them on to agents, don't describe them.
        \(flows.isEmpty ? "" : "\nSaved workflows:\n" + flows)
        """
    }

    static let escalationPrompt = "You are Haku's deeper-thinking model. Answer carefully but concisely; prefer short paragraphs. Wrap paths in backticks; highlight the key phrase with ==double equals==. No other markdown."

    /// Prompt used to turn a workflow's agent template into a task (kept identical for retries).
    static func agentTask(from template: String) -> String { template }
}
