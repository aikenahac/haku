import AppKit
import Foundation
import Observation

/// The app's brain stem: conversation, voice turn-taking, workflows, jobs, and the widget state they add up to.
@MainActor
@Observable
final class AppModel: BrainHost {
    enum Fix: Equatable { case micSettings, speechSettings, modelSettings, retry, openSettings }

    // Services
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let themes: ThemeManager
    @ObservationIgnored let voice: VoicePipeline
    @ObservationIgnored let brain: Brain
    let conversations = ConversationStore()
    @ObservationIgnored private var brainConversationID: UUID?
    @ObservationIgnored let attachmentsStore = AttachmentStore()
    let workflows = WorkflowStore()
    let tasks = TaskStore()
    let confirmations = ConfirmationCenter()
    @ObservationIgnored let runner: AgentRunner
    let wake = WakeWordService()
    @ObservationIgnored private var wakePaused = false

    // Conversation (the current one; the main window can switch it)
    var messages: [ChatMessage] { conversations.current?.messages ?? [] }
    var draft = ""
    private(set) var pendingAttachments: [Attachment] = []
    private(set) var thinking = false
    private(set) var thinkingLabel: String?
    private(set) var error: (reason: String, fix: Fix)?
    private(set) var modelOnline: Bool?
    private(set) var hovering = false
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var lastFailedInput: (text: String, spoken: Bool, conversation: UUID)?
    @ObservationIgnored private var confirmListenTask: Task<Void, Never>?
    @ObservationIgnored private var errorClearTask: Task<Void, Never>?
    @ObservationIgnored private var talkPressedAt: Date?

    // Window hooks (set by the AppDelegate).
    @ObservationIgnored var showPanel: () -> Void = {}
    @ObservationIgnored var togglePanel: () -> Void = {}
    @ObservationIgnored var showTasks: (UUID?) -> Void = { _ in }
    @ObservationIgnored var showSettings: (String?) -> Void = { _ in }

    init(settings: AppSettings, themes: ThemeManager) {
        self.settings = settings
        self.themes = themes
        voice = VoicePipeline(settings: settings)
        brain = Brain(settings: settings)
        runner = AgentRunner(store: tasks, settings: settings)
        brain.host = self
        runner.onFinish = { [weak self] job in self?.jobFinished(job) }
        conversations.persist = settings.keepHistory
        if let c = conversations.current { brain.seed(c.messages); brainConversationID = c.id }
        attachmentsStore.purgeAll()
        wake.onWake = { [weak self] after in self?.wakeHeard(after) }
    }

    // MARK: Wake word

    /// Starts/stops the detector to match settings and permissions; pauses it while Haku is busy with audio.
    func syncWakeWord() {
        wake.sensitivity = settings.wakeSensitivity
        wake.locale = settings.primaryLocale
        if settings.wakeWordEnabled && settings.onboardingDone && Permissions.microphone == .allowed {
            if wake.status == .off || { if case .unavailable = wake.status { return true }; return false }() { wake.start() }
        } else if wake.status != .off {
            wake.stop()
        }
    }

    /// Called from an observation loop: pause detection while listening, speaking or confirming.
    func updateWakePause() {
        let busy = voice.phase != .idle || confirmations.current != nil
        if busy && !wakePaused { wakePaused = true; wake.pause() }
        else if !busy && wakePaused { wakePaused = false; wake.resume() }
    }

    private func wakeHeard(_ after: String?) {
        guard confirmations.current == nil, !voice.isListening else { return }
        voice.stopSpeaking()
        if let after, after.split(separator: " ").count >= 2 {
            send(after, spoken: true, origin: .voiceTrigger)
        } else {
            startHandsFree()
        }
    }

    /// Listens after the wake word and stops on its own once you've finished speaking.
    func startHandsFree() {
        NSSound(named: "Tink")?.play()
        clearError()
        Task {
            do { try await voice.beginListening() } catch { handleVoiceError(error); return }
            let start = Date.now
            var lastText = ""
            var lastChange = Date.now
            while voice.isListening {
                try? await Task.sleep(for: .milliseconds(120))
                let text = voice.partial.trimmingCharacters(in: .whitespacesAndNewlines)
                if text != lastText { lastText = text; lastChange = .now }
                let elapsed = Date.now.timeIntervalSince(start)
                if text.isEmpty && elapsed > 6 { voice.cancelListening(); return }            // nothing said
                if !text.isEmpty && Date.now.timeIntervalSince(lastChange) > 1.3 && voice.level < 0.35 { break } // finished
                if elapsed > 25 { break }
            }
            guard voice.isListening else { return }
            let text = await voice.endListening()
            if !text.isEmpty { send(text, spoken: true, origin: .voiceTrigger) }
        }
    }

    // MARK: Widget state

    var widgetState: WidgetState {
        if let error { return .error(reason: error.reason) }
        if voice.isListening {
            return .listening(level: voice.level, elapsed: voice.listeningSince.map { Date.now.timeIntervalSince($0) } ?? 0)
        }
        if voice.phase == .speaking { return .speaking }
        if thinking || voice.phase == .transcribing { return .thinking }
        let running = tasks.running
        if let first = running.first {
            let p = first.stepProgress
            return .agentRunning(agent: first.runner.displayName, done: p.done, total: max(p.total, p.done), jobs: running.count)
        }
        return .idle
    }

    /// Opacity snaps to 100% on hover, while talking, or when something needs attention.
    var widgetFullyOpaque: Bool {
        hovering || widgetState.needsAttention || confirmations.current != nil
            || tasks.jobs.contains { $0.status == .awaitingApproval }
    }

    func setHovering(_ h: Bool) { hovering = h }

    var marginNotes: [UUID: MarginNote] {
        var out: [UUID: MarginNote] = [:]
        for j in tasks.jobs {
            guard let mid = j.messageID else { continue }
            out[jobNoteKey(mid)] = MarginNote(id: j.id, agent: j.runner.displayName, status: j.statusLine,
                                              detail: j.marginDetail, running: j.isActive || j.status == .awaitingApproval)
        }
        return out
    }

    /// Margin notes are keyed by the message's jobID (= message id of the reply).
    private func jobNoteKey(_ messageID: UUID) -> UUID { messageID }

    // MARK: Voice turn-taking

    func talkPressed() {
        talkPressedAt = .now
        clearError()
        voice.stopSpeaking()
        if confirmations.current != nil {
            confirmListenTask?.cancel()
            voice.cancelListening()
        }
        Task {
            do { try await voice.beginListening() } catch { handleVoiceError(error) }
        }
    }

    func talkReleased() {
        guard voice.isListening else { return }
        let pressed = talkPressedAt
        Task {
            // Very short taps shouldn't send half a word; give the recognizer a moment.
            if let pressed, Date.now.timeIntervalSince(pressed) < 0.35 { try? await Task.sleep(for: .milliseconds(250)) }
            let text = await voice.endListening()
            guard !text.isEmpty else { return }
            if confirmations.current != nil {
                if !confirmations.handleSpoken(text) { /* not a yes/no; keep the slip up */ }
                return
            }
            send(text, spoken: true, origin: .voiceTrigger)
        }
    }

    func stopSpeaking() { voice.stopSpeaking() }

    private func handleVoiceError(_ error: Error) {
        if let v = error as? VoiceError {
            switch v {
            case .micDenied, .micUnavailable: setError(v.widgetReason, fix: .micSettings)
            case .speechDenied: setError(v.widgetReason, fix: .speechSettings)
            default: setError(v.widgetReason, fix: .openSettings)
            }
        } else {
            setError("mic unavailable", fix: .micSettings)
        }
    }

    // MARK: Sending

    func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        draft = ""
        send(text.isEmpty ? "What's this?" : text, spoken: false)
    }

    /// Where an input came from: voice triggers start a fresh chat (unless it's a quick follow-up); typing continues the visible one.
    enum InputOrigin { case voiceTrigger, typed }

    func send(_ text: String, spoken: Bool, origin: InputOrigin = .typed, in conversationID: UUID? = nil) {
        clearError()
        let attachments = pendingAttachments
        pendingAttachments = []
        let convo = conversationID.flatMap(conversations.conversation)
            ?? (origin == .voiceTrigger ? conversations.forVoiceTrigger() : conversations.currentForSending())
        conversations.currentID = convo.id
        if brainConversationID != convo.id {
            brain.seed(convo.messages)
            brainConversationID = convo.id
        }
        let cid = convo.id
        let user = ChatMessage(role: .user, spans: [.text(text)], attachments: attachments)
        conversations.append(user, to: cid)
        lastFailedInput = (text, spoken, cid)

        let speak = settings.speakReplies == .always || (settings.speakReplies == .whenISpoke && spoken)
        turnTask?.cancel()
        turnTask = Task {
            thinking = true
            defer { thinking = false; thinkingLabel = nil }
            let replyID = UUID()
            var reply = ChatMessage(id: replyID, role: .haku, spans: [], jobID: replyID)
            let show: (String) -> Void = { [weak self] text in
                guard let self else { return }
                reply.spans = MessageSpan.parse(text)
                self.conversations.replace(reply, in: cid)
            }

            // Exact workflow trigger wins before the model.
            if let (flow, after) = workflows.match(text) {
                let result = await executeWorkflow(flow, after: after, messageID: replyID, attachments: attachments)
                show(result)
                finishTurn(reply, in: cid)
                if speak { Task { await voice.speak(result, allowVoiceBargeIn: spoken) } }
                return
            }

            // Speech starts with the first finished sentence, while the rest is still streaming.
            let speechID = speak ? voice.beginSpokenReply(allowVoiceBargeIn: spoken) : nil
            do {
                let r = try await brain.respond(to: text, attachments: attachments, messageID: replyID,
                                                onDelta: { [weak self] s in
                                                    show(s)
                                                    if let speechID { self?.voice.appendReplyText(speechID, s) }
                                                },
                                                onStatus: { [weak self] s in self?.thinkingLabel = s.isEmpty ? nil : s })
                show(r.text)
                lastFailedInput = nil
                if r.startedJob == nil { attachmentsStore.discard(attachments) }
                finishTurn(reply, in: cid)
                if let speechID { Task { await voice.endSpokenReply(speechID, finalText: r.text) } }
            } catch is CancellationError {
                if let speechID { voice.cancelSpokenReply(speechID) }
            } catch let e as LLMError {
                if let speechID { voice.cancelSpokenReply(speechID) }
                modelOnline = false
                setError(e.widgetReason, fix: .modelSettings)
                show(e.localizedDescription.prefix(1).uppercased() + e.localizedDescription.dropFirst() + ". Check Settings › Models & agents.")
                attachmentsStore.discard(attachments)
            } catch {
                if let speechID { voice.cancelSpokenReply(speechID) }
                setError("something broke", fix: .retry)
                attachmentsStore.discard(attachments)
            }
        }
    }

    private func finishTurn(_ reply: ChatMessage, in cid: UUID) {
        guard let convo = conversations.conversation(cid),
              convo.messages.contains(where: { $0.id == reply.id }) else { return }
        // Let the model name the chat once it has a first exchange.
        if !convo.titled, let first = convo.entries.first(where: { $0.role == .user }) {
            Task {
                let t = await brain.title(for: first.text)
                conversations.rename(cid, to: t, byModel: true)
            }
        }
    }

    func retryLast() {
        // Retry in the chat it failed in, not a fresh one.
        guard let last = lastFailedInput else { return }
        send(last.text, spoken: last.spoken, in: last.conversation)
    }

    /// Starts a fresh chat (widget panel "new chat", ⌘N).
    func newConversation() {
        conversations.newConversation()
        brain.reset()
        brainConversationID = conversations.currentID
    }

    /// Makes a past chat current so the widget and panel continue it.
    func selectConversation(_ id: UUID) {
        guard conversations.currentID != id, let c = conversations.conversation(id) else { return }
        conversations.currentID = id
        brain.seed(c.messages)
        brainConversationID = id
    }

    func deleteConversation(_ id: UUID) {
        conversations.delete(id)
        if brainConversationID == id { brain.reset(); brainConversationID = nil }
    }

    func clearConversation() {
        conversations.deleteAll()
        brain.reset()
        brainConversationID = nil
    }

    // MARK: Errors

    func setError(_ reason: String, fix: Fix) {
        error = (reason, fix)
        errorClearTask?.cancel()
        errorClearTask = Task {
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { self.error = nil }
        }
    }

    func clearError() { error = nil; errorClearTask?.cancel() }

    func fixError() {
        guard let fix = error?.fix else { return }
        clearError()
        switch fix {
        case .micSettings: Permissions.openSettings("Privacy_Microphone")
        case .speechSettings: Permissions.openSettings("Privacy_SpeechRecognition")
        case .modelSettings: showSettings("Models & agents")
        case .openSettings: showSettings(nil)
        case .retry: retryLast()
        }
    }

    // MARK: Model status

    func refreshModelStatus() async {
        do {
            let ids = try await brain.client.models()
            modelOnline = true
            availableModels = ids
        } catch {
            modelOnline = false
            // LM Studio's port is configurable (Bionic often uses 1235): look for it nearby.
            if settings.serverType == .lmStudio, let found = await Self.findLocalServer(excluding: settings.endpoint) {
                Log.info("model server not at \(settings.endpoint); found it at \(found)")
                settings.endpoint = found
                await refreshModelStatus()
            }
        }
    }

    /// Probes common local OpenAI-compatible ports and returns the first that answers `/v1/models`.
    static func findLocalServer(excluding current: String) async -> String? {
        for port in [1234, 1235, 1236, 1237, 8080, 11434] {
            let url = "http://localhost:\(port)/v1"
            if url == current { continue }
            if (try? await OpenAIClient(endpoint: url).models()) != nil { return url }
        }
        return nil
    }

    private(set) var availableModels: [String] = []

    /// Header label, e.g. "GEMMA 4 LOCAL".
    var modelDisplayName: String {
        let id = settings.routingModel
        if id.lowercased().contains("gemma-4") || id.lowercased().contains("gemma4") { return "Gemma 4 local" }
        return id + (modelOnline == false ? " · offline" : "")
    }

    // MARK: Attachments

    func attach(urls: [URL]) {
        for u in urls {
            if let a = try? attachmentsStore.importFile(u) { pendingAttachments.append(a) }
        }
        if !urls.isEmpty { showPanel() }
    }

    func attach(image: NSImage, name: String = "pasted.png") {
        if let a = try? attachmentsStore.importImage(image, name: name) { pendingAttachments.append(a) }
    }

    func attachScreenshot() {
        Task {
            if Permissions.screenRecording != .allowed, !Permissions.requestScreenRecording() {
                setError("screen recording off", fix: .openSettings)
                Permissions.openSettings("Privacy_ScreenCapture")
                return
            }
            do {
                let img = try await Screenshot.captureMainDisplay()
                attach(image: img, name: "screenshot-\(Date.now.formatted(.iso8601.time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")).png")
                showPanel()
            } catch {
                setError("screenshot failed", fix: .openSettings)
            }
        }
    }

    func removeAttachment(_ id: UUID) {
        guard let a = pendingAttachments.first(where: { $0.id == id }) else { return }
        pendingAttachments.removeAll { $0.id == id }
        attachmentsStore.discard([a])
    }

    // MARK: BrainHost

    var workflowList: [Workflow] { workflows.workflows }

    func searchHistory(_ query: String) -> String {
        conversations.searchSnippets(query, excluding: conversations.currentID)
    }

    func confirm(_ request: ConfirmationRequest) async -> ConfirmationDecision {
        let decision = await confirmations.ask(request)
        confirmListenTask?.cancel()
        if voice.isListening { voice.cancelListening() }
        return decision
    }

    /// Called by the confirmation window when a slip appears: listens for "yes"/"no" if enabled.
    func confirmationPresented() {
        guard settings.confirmByVoice, Permissions.microphone == .allowed else { return }
        confirmListenTask?.cancel()
        confirmListenTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            do { try await voice.beginListening() } catch { return }
            let deadline = Date.now.addingTimeInterval(10)
            let request = confirmations.current?.id
            var candidate: (String, Date)?
            while !Task.isCancelled, Date.now < deadline, confirmations.current?.id == request {
                let heard = voice.partial
                if ConfirmationCenter.classify(heard) != nil {
                    // Only act once the recognizer has settled on the same short phrase for half a second.
                    if let c = candidate, c.0 == heard, Date.now.timeIntervalSince(c.1) > 0.5 {
                        confirmations.handleSpoken(heard)
                        break
                    }
                    if candidate?.0 != heard { candidate = (heard, .now) }
                } else {
                    candidate = nil
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            if voice.isListening { voice.cancelListening() }
        }
    }

    func delegate(agent: AgentKind?, task: String, directory: String?, spokenAsk: String,
                  attachments: [Attachment], messageID: UUID) async -> DelegationOutcome {
        await delegate(agent: agent, task: task, directory: directory, spokenAsk: spokenAsk, attachments: attachments,
                       messageID: messageID, edits: nil, skipConfirm: false, source: "Agent delegation")
    }

    func delegate(agent requested: AgentKind?, task: String, directory: String?, spokenAsk: String,
                  attachments: [Attachment], messageID: UUID, edits: EditPermission?, skipConfirm: Bool,
                  source: String) async -> DelegationOutcome {
        var agent = requested ?? (settings.claude.enabled ? .claude : .codex)
        if !settings.agent(agent).enabled { agent = agent == .claude ? .codex : .claude }
        guard settings.agent(agent).enabled else { return .failed("no coding agent is enabled") }
        var folder = (directory?.isEmpty == false ? directory! : settings.defaultFolder)
        if folder == settings.defaultFolder { settings.ensureDefaultFolder() }
        var permission = edits ?? settings.agent(agent).defaultEdits

        if !skipConfirm {
            let d = await confirm(ConfirmationRequest(kind: .agent(prompt: task, agent: agent, folder: folder, edits: permission),
                                                      source: source, question: "Hand this to \(agent.displayName)?"))
            guard d.approved else { return .declined }
            agent = d.agent ?? agent
            folder = d.folder ?? folder
            permission = d.edits ?? permission
        }

        var job = AgentJob(runner: agent == .claude ? .claude : .codex, title: String(task.prefix(60)), prompt: task,
                           spokenAsk: spokenAsk, directory: folder.abbreviatingHome, permission: permission)
        job.attachmentPaths = attachments.compactMap { $0.url?.path }
        job.messageID = messageID
        tasks.add(job)
        attachmentsStore.retain(attachments, for: job.id)
        let id = job.id
        Task {
            let title = await brain.title(for: task)
            tasks.update(id) { $0.title = title }
        }
        startOrQueue(id)
        return .started(tasks.job(id) ?? job)
    }

    private func startOrQueue(_ id: UUID) {
        if runner.runningCount < max(1, settings.maxConcurrentJobs) {
            runner.start(id)
        } else {
            tasks.update(id) { $0.status = .queued; $0.log.append(.init(date: .now, text: "queued — another job is running", kind: .info)) }
        }
    }

    func runWorkflow(named name: String, after: String, messageID: UUID) async -> String {
        guard let w = workflows.workflow(named: name) else { return "no workflow called \(name)" }
        return await executeWorkflow(w, after: after, messageID: messageID, attachments: [])
    }

    /// Runs a workflow from the panel link or hotkey.
    func runWorkflowFromUI(_ id: UUID) {
        guard let w = workflows.workflows.first(where: { $0.id == id }) else { return }
        send(w.primaryPhrase, spoken: false)
    }

    func runWorkflowFromUI(named name: String) {
        guard let w = workflows.workflow(named: name) else { return }
        send(w.primaryPhrase, spoken: false)
    }

    func executeWorkflow(_ w: Workflow, after: String, messageID: UUID, attachments: [Attachment]) async -> String {
        let body = ContextVariables.expand(w.template, after: after)
        let skip = !w.confirmBeforeRunning || w.alwaysAllow
        switch w.action {
        case .askModel:
            do {
                return try await brain.client.complete(model: try await brain.routingKey(),
                                                       messages: [.system("You are Haku. Be concise. Wrap paths in backticks."), .user(body)])
            } catch {
                setError("model offline", fix: .modelSettings)
                return "The model isn't answering."
            }
        case .shell, .script:
            if !skip {
                let consequences = await CommandRisk.assess(body, cwd: w.folder)
                let kind: ConfirmationRequest.Kind = w.action == .shell
                    ? .shell(command: body, cwd: w.folder)
                    : .script(name: w.name, body: body, cwd: w.folder)
                let d = await confirm(ConfirmationRequest(
                    kind: kind,
                    source: "\(w.action == .shell ? "Shell command" : "Script") · workflow “\(w.name)”",
                    question: w.action == .shell ? "Run this command?" : "Run this script?",
                    consequences: consequences,
                    alwaysAllowLabel: w.action == .shell ? "Don't ask again for this workflow" : "Don't ask again for this script",
                    workflowID: w.id))
                guard d.approved else { return "Okay, didn't run it." }
                if d.alwaysAllow { var u = w; u.alwaysAllow = true; workflows.upsert(u) }
            }
            let r = await ShellRunner.run(body, cwd: w.folder, timeout: 600)
            let last = r.output.split(separator: "\n").last.map(String.init) ?? ""
            return r.exitCode == 0
                ? "Done\(last.isEmpty ? "." : ": \(last.prefix(140))")"
                : "That failed (exit \(r.exitCode))\(last.isEmpty ? "." : ": ==\(last.prefix(120))==")"
        case .agent:
            let outcome = await delegate(agent: w.agent, task: body, directory: w.folder, spokenAsk: w.primaryPhrase + (after.isEmpty ? "" : " " + after),
                                         attachments: attachments, messageID: messageID,
                                         edits: w.allowEditsWithoutAsking ? .allowed : nil, skipConfirm: skip,
                                         source: "Agent delegation · workflow “\(w.name)”")
            switch outcome {
            case .started(let job):
                return "Handed to \(job.runner.displayName) in `\(job.directory ?? "~")`. I'll note it in the margin when it's done."
            case .declined: return "Okay, not sending it."
            case .failed(let why): return "Couldn't start that: \(why)"
            }
        }
    }

    // MARK: Jobs

    func cancelJob(_ id: UUID) { runner.cancel(id) }

    func retryJob(_ id: UUID) {
        guard let old = tasks.job(id) else { return }
        var job = AgentJob(runner: old.runner, title: old.title, prompt: old.prompt, spokenAsk: old.spokenAsk,
                           directory: old.directory, permission: old.permission)
        job.messageID = old.messageID
        tasks.add(job)
        startOrQueue(job.id)
    }

    func approveEdits(_ id: UUID) {
        guard let job = tasks.job(id), job.status == .awaitingApproval else { return }
        Log.info("applying approved edits: \(job.title)")
        // Dismiss a pending "Apply these changes?" slip if the Tasks button was used instead.
        if case .applyEdits = confirmations.current?.kind { confirmations.deny(source: "superseded") }
        runner.start(id, resume: true)
    }

    @ObservationIgnored private var handledFinishes: Set<String> = []

    private func jobFinished(_ job: AgentJob) {
        // One report per run (a resumed run has a higher approval count).
        guard handledFinishes.insert("\(job.id)-\(job.approvals)").inserted else { return }
        Log.info("job finished: \(job.title) → \(job.status.rawValue)")
        attachmentsStore.release(job: job.id)
        // Start the next queued job.
        if let next = tasks.jobs.last(where: { $0.status == .queued }) { startOrQueue(next.id) }
        guard job.status != .cancelled else { return }

        Task {
            let sentence = await brain.spokenSummary(of: job)
            let title = job.status == .failed ? "\(job.runner.displayName) failed" : job.status == .awaitingApproval
                ? "\(job.runner.displayName) has changes to approve" : "\(job.runner.displayName) finished"
            Notifier.post(title: title, body: "\(job.title) — \(sentence)", id: job.id.uuidString)
            if settings.speakReplies != .never { await voice.speak(sentence, allowVoiceBargeIn: false) }

            if job.status == .awaitingApproval {
                let d = await confirm(ConfirmationRequest(
                    kind: .applyEdits(jobTitle: job.title, agent: job.runner.displayName, proposal: job.summary ?? ""),
                    source: "\(job.runner.displayName) · \(job.directory ?? "")", question: "Apply these changes?"))
                if d.approved { approveEdits(job.id) } else if tasks.job(job.id)?.status == .awaitingApproval {
                    tasks.update(job.id) { $0.status = .done; $0.log.append(.init(date: .now, text: "changes not applied", kind: .info)) }
                }
            }
        }
    }
}
