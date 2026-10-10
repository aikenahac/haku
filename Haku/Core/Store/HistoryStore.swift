import Foundation

/// Text-only conversation history. Attachments are never stored, only their file names.
@MainActor
final class HistoryStore {
    struct Entry: Codable {
        var id: UUID
        var role: ChatMessage.Role
        var text: String
        var marks: [String]
        var attachmentNames: [String]
        var date: Date
    }

    private(set) var entries: [Entry] = []
    private let url: URL
    private let limit = 500

    init(url: URL = AppPaths.history) {
        self.url = url
        entries = JSONFile.load([Entry].self, from: url) ?? []
    }

    func messages(last n: Int = 60) -> [ChatMessage] {
        entries.suffix(n).map { e in
            // `text` keeps the ==mark== / `path` markup so styling survives a relaunch.
            var spans = MessageSpan.parse(e.text)
            if !e.marks.isEmpty, !e.text.contains("==") { spans = MessageSpan.parse(e.text, marks: e.marks) }
            let names = e.attachmentNames.map { Attachment(fileName: $0, url: nil, isImage: false) }
            return ChatMessage(id: e.id, role: e.role, spans: spans, attachments: names)
        }
    }

    func append(_ m: ChatMessage) {
        let marks = m.spans.compactMap { if case .mark(let s) = $0 { s } else { nil } }
        entries.append(Entry(id: m.id, role: m.role, text: m.markup, marks: marks,
                             attachmentNames: m.attachments.map(\.fileName), date: .now))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        JSONFile.save(entries, to: url)
    }

    func replace(_ m: ChatMessage) {
        guard let i = entries.firstIndex(where: { $0.id == m.id }) else { return append(m) }
        let marks = m.spans.compactMap { if case .mark(let s) = $0 { s } else { nil } }
        entries[i].text = m.markup
        entries[i].marks = marks
        JSONFile.save(entries, to: url)
    }

    func clear() {
        entries = []
        JSONFile.save(entries, to: url)
    }
}

extension MessageSpan {
    /// Splits text into spans: `==marked==` → mark, `` `path` `` → path. Used for model output.
    static func parse(_ text: String) -> [MessageSpan] {
        var spans: [MessageSpan] = []
        var buf = ""
        var i = text.startIndex
        func flush() { if !buf.isEmpty { spans.append(.text(buf)); buf = "" } }
        while i < text.endIndex {
            if text[i...].hasPrefix("=="), let end = text[text.index(i, offsetBy: 2)...].range(of: "==") {
                flush()
                spans.append(.mark(String(text[text.index(i, offsetBy: 2)..<end.lowerBound])))
                i = end.upperBound
            } else if text[i] == "`", let end = text[text.index(after: i)...].firstIndex(of: "`") {
                flush()
                spans.append(.path(String(text[text.index(after: i)..<end])))
                i = text.index(after: end)
            } else if text[i...].hasPrefix("**"), let end = text[text.index(i, offsetBy: 2)...].range(of: "**") {
                // Bold has no place in this voice; render as a mark.
                flush()
                spans.append(.mark(String(text[text.index(i, offsetBy: 2)..<end.lowerBound])))
                i = end.upperBound
            } else {
                buf.append(text[i])
                i = text.index(after: i)
            }
        }
        flush()
        return spans
    }

    /// Re-applies stored marks to plain text.
    static func parse(_ text: String, marks: [String]) -> [MessageSpan] {
        var marked = text
        for m in Set(marks) where !m.isEmpty { marked = marked.replacingOccurrences(of: m, with: "==\(m)==") }
        return parse(marked)
    }
}
