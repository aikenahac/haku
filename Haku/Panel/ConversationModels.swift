import Foundation

/// An inline span in a message: plain, highlighted, or a mono path.
enum MessageSpan: Equatable, Sendable, Hashable {
    case text(String)
    case mark(String)
    case path(String)
}

struct Attachment: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    var fileName: String
    var url: URL?
    var isImage: Bool

    init(id: UUID = UUID(), fileName: String, url: URL? = nil, isImage: Bool = true) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.isImage = isImage
    }
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable, Codable { case user, haku }
    let id: UUID
    var role: Role
    var spans: [MessageSpan]
    var attachments: [Attachment] = []
    /// A job started by this message gets its note lined up beside it in the margin.
    var jobID: UUID?

    init(id: UUID = UUID(), role: Role, spans: [MessageSpan], attachments: [Attachment] = [], jobID: UUID? = nil) {
        self.id = id
        self.role = role
        self.spans = spans
        self.attachments = attachments
        self.jobID = jobID
    }

    init(_ role: Role, _ text: String) {
        self.init(role: role, spans: [.text(text)])
    }

    /// Text with `==mark==` and `` `path` `` markup (what's stored in history).
    var markup: String {
        spans.map {
            switch $0 {
            case .text(let s): s
            case .mark(let s): "==\(s)=="
            case .path(let s): "`\(s)`"
            }
        }.joined()
    }

    var plainText: String {
        spans.map {
            switch $0 {
            case .text(let s), .mark(let s), .path(let s): s
            }
        }.joined()
    }
}

/// A running or finished agent job as shown in the panel margin.
struct MarginNote: Identifiable, Equatable, Sendable {
    let id: UUID
    var agent: String
    var status: String
    var detail: String?
    var running: Bool
}

enum SampleConversation {
    static let jobID = UUID()

    static let messages: [ChatMessage] = [
        ChatMessage(.user, "Run the devenv tests and tell me what's failing."),
        ChatMessage(role: .haku, spans: [.text("Handed to Claude Code in "), .path("~/code/devenv"),
                                         .text(". I'll note it in the margin when it's done.")], jobID: jobID),
        ChatMessage(role: .user, spans: [.text("What's this one about?")],
                    attachments: [Attachment(fileName: "caddy-error.png")]),
        ChatMessage(role: .haku, spans: [.text("Caddy can't get a cert for staging — the "), .mark("A record"),
                                         .text(" still points at the old IP.")]),
    ]

    static let notes: [UUID: MarginNote] = [
        jobID: MarginNote(id: jobID, agent: "Claude Code", status: "running · step 2 of 5",
                          detail: "41 passed, 3 failed", running: true),
    ]

    static let workflows = ["standup", "deploy staging", "tidy downloads"]
}
