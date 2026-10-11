import Foundation
import Observation

/// One chat thread. Typed input continues the current one; voice triggers start fresh unless it's a quick follow-up.
struct Conversation: Codable, Identifiable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var id: UUID
        var role: ChatMessage.Role
        /// Text with ==mark== / `path` markup.
        var text: String
        var attachmentNames: [String]
        var jobID: UUID?
        var date: Date
    }

    var id = UUID()
    var title: String
    var created: Date = .now
    var updated: Date = .now
    var entries: [Entry] = []
    /// True once the model has suggested a title (don't overwrite user edits).
    var titled = false
    var pinned = false

    var messages: [ChatMessage] {
        entries.map { e in
            ChatMessage(id: e.id, role: e.role, spans: MessageSpan.parse(e.text),
                        attachments: e.attachmentNames.map { Attachment(fileName: $0, url: nil, isImage: false) },
                        jobID: e.jobID)
        }
    }

    var preview: String {
        let last = entries.last(where: { $0.role == .haku }) ?? entries.last
        return (last?.text ?? "").replacingOccurrences(of: "==", with: "").replacingOccurrences(of: "`", with: "")
    }

    static func provisionalTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(7).joined(separator: " ")
        let t = words.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return t.isEmpty ? "New chat" : t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// Stores conversations as JSON files in Application Support/Haku/conversations (text only).
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    var currentID: UUID?
    /// Off when "Keep history" is off: chats live in memory only.
    @ObservationIgnored var persist = true
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]
    /// A new chat starts automatically after this much quiet.
    static let idleGap: TimeInterval = 2 * 3600
    /// A voice trigger continues the current chat only within this long of its last message.
    static let followUpGap: TimeInterval = 120
    /// Clock (tests move it forward).
    @ObservationIgnored var now: () -> Date = { .now }

    init(directory: URL = AppPaths.support.appendingPathComponent("conversations", isDirectory: true)) {
        dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        conversations = files.filter { $0.pathExtension == "json" }
            .compactMap { JSONFile.load(Conversation.self, from: $0) }
            .sorted { $0.updated > $1.updated }
        migrateLegacyHistory()
        currentID = conversations.first?.id
    }

    var current: Conversation? { conversations.first { $0.id == currentID } }

    func conversation(_ id: UUID) -> Conversation? { conversations.first { $0.id == id } }

    /// The conversation the next message belongs to (starts a new one after a long gap).
    func currentForSending() -> Conversation {
        if let c = current, now().timeIntervalSince(c.updated) < Self.idleGap || c.entries.isEmpty { return c }
        return newConversation()
    }

    /// The conversation a wake word / push-to-talk command belongs to: fresh, unless it follows right on the last exchange.
    func forVoiceTrigger() -> Conversation {
        if let c = current, c.entries.isEmpty || now().timeIntervalSince(c.updated) < Self.followUpGap { return c }
        return newConversation()
    }

    @discardableResult
    func newConversation() -> Conversation {
        if let c = current, c.entries.isEmpty { return c }
        var c = Conversation(title: "New chat")
        c.created = now(); c.updated = now()
        conversations.insert(c, at: 0)
        currentID = c.id
        save(c.id)
        return c
    }

    func append(_ m: ChatMessage, to id: UUID) {
        update(id) { c in
            c.entries.append(.init(id: m.id, role: m.role, text: m.markup, attachmentNames: m.attachments.map(\.fileName),
                                   jobID: m.jobID, date: now()))
            if c.title == "New chat", m.role == .user { c.title = Conversation.provisionalTitle(from: m.plainText) }
        }
    }

    func replace(_ m: ChatMessage, in id: UUID) {
        update(id) { c in
            if let i = c.entries.firstIndex(where: { $0.id == m.id }) {
                c.entries[i].text = m.markup
            } else {
                c.entries.append(.init(id: m.id, role: m.role, text: m.markup, attachmentNames: [], jobID: m.jobID, date: now()))
            }
        }
    }

    func rename(_ id: UUID, to title: String, byModel: Bool = false) {
        update(id, touch: false) { c in
            guard !byModel || !c.titled else { return }
            c.title = title
            c.titled = true
        }
    }

    func togglePin(_ id: UUID) { update(id, touch: false) { $0.pinned.toggle() } }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: file(id))
        if currentID == id { currentID = conversations.first?.id }
    }

    func deleteAll() {
        for c in conversations { try? FileManager.default.removeItem(at: file(c.id)) }
        conversations = []
        currentID = nil
    }

    func search(_ q: String) -> [Conversation] {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return conversations }
        return conversations.filter { c in
            c.title.lowercased().contains(t) || c.entries.contains { $0.text.lowercased().contains(t) }
        }
    }

    /// Earlier chats mentioning the query's words, as short plain-text excerpts for the model.
    /// Ranked by how many distinct words hit, then recency; capped at `maxChars`.
    func searchSnippets(_ query: String, excluding: UUID?, limit: Int = 3, maxChars: Int = 1500) -> String {
        let words = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 })
        guard !words.isEmpty else { return "no earlier chats matched" }
        let plain: (String) -> String = { $0.replacingOccurrences(of: "==", with: "").replacingOccurrences(of: "`", with: "") }
        var scored: [(convo: Conversation, hits: Int)] = []
        for c in conversations where c.id != excluding {
            let text = (c.title + " " + c.entries.map(\.text).joined(separator: " ")).lowercased()
            let hits = words.filter { text.contains($0) }.count
            if hits > 0 { scored.append((c, hits)) }
        }
        scored.sort { a, b in a.hits != b.hits ? a.hits > b.hits : a.convo.updated > b.convo.updated }
        let ranked = scored.prefix(limit)
        guard !ranked.isEmpty else { return "no earlier chats matched" }
        let fmt = RelativeDateTimeFormatter()
        var out = ""
        for (c, _) in ranked {
            var block = "Chat \"\(c.title)\" (\(fmt.localizedString(for: c.updated, relativeTo: now()))):\n"
            // Matching entries plus the turn after each (usually Haku's answer).
            var picked = IndexSet()
            for (i, e) in c.entries.enumerated() where words.contains(where: e.text.lowercased().contains) {
                picked.insert(i)
                if i + 1 < c.entries.count { picked.insert(i + 1) }
            }
            if picked.isEmpty { picked.insert(integersIn: 0..<min(2, c.entries.count)) }
            for i in picked {
                let e = c.entries[i]
                block += "\(e.role == .user ? "User" : "Haku"): \(plain(e.text).prefix(300))\n"
            }
            if out.count + block.count > maxChars {
                if out.isEmpty { out = String(block.prefix(maxChars)) }
                break
            }
            out += block + "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func update(_ id: UUID, touch: Bool = true, _ change: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[i])
        if touch {
            conversations[i].updated = now()
            // Most recent first.
            let c = conversations.remove(at: i)
            conversations.insert(c, at: 0)
        }
        save(id)
    }

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).json") }

    private func save(_ id: UUID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, self.persist, let c = self.conversation(id) else { return }
            JSONFile.save(c, to: self.file(id))
        }
    }

    /// Moves the old flat history.json into a single conversation (one time).
    private func migrateLegacyHistory() {
        let legacy = AppPaths.history
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let old = HistoryStore(url: legacy)
        if !old.entries.isEmpty {
            var c = Conversation(title: Conversation.provisionalTitle(from: old.entries.first { $0.role == .user }?.text ?? "Earlier chats"))
            c.created = old.entries.first?.date ?? .now
            c.updated = old.entries.last?.date ?? .now
            c.entries = old.entries.map { .init(id: $0.id, role: $0.role, text: $0.text, attachmentNames: $0.attachmentNames, jobID: nil, date: $0.date) }
            conversations.insert(c, at: 0)
            conversations.sort { $0.updated > $1.updated }
            JSONFile.save(c, to: file(c.id))
        }
        try? FileManager.default.moveItem(at: legacy, to: legacy.appendingPathExtension("migrated"))
    }
}
