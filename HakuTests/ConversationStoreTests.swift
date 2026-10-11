import XCTest
@testable import Haku

@MainActor
final class ConversationStoreTests: XCTestCase {
    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("haku-convo-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> ConversationStore {
        let s = ConversationStore(directory: dir)
        s.persist = false
        s.now = { [unowned self] in self.clock }
        return s
    }

    private func say(_ s: ConversationStore, _ text: String, role: ChatMessage.Role = .user, in id: UUID) {
        s.append(ChatMessage(role: role, spans: [.text(text)]), to: id)
    }

    func testVoiceTriggerContinuesQuickFollowUp() {
        let s = makeStore()
        let a = s.newConversation()
        say(s, "Open Safari", in: a.id)
        clock += 60
        XCTAssertEqual(s.forVoiceTrigger().id, a.id)
    }

    func testVoiceTriggerStartsFreshAfterGap() {
        let s = makeStore()
        let a = s.newConversation()
        say(s, "Open Safari", in: a.id)
        clock += ConversationStore.followUpGap + 1
        let b = s.forVoiceTrigger()
        XCTAssertNotEqual(b.id, a.id)
        XCTAssertEqual(s.currentID, b.id)
        // Typing would still have continued the old one.
        s.currentID = a.id
        XCTAssertEqual(s.currentForSending().id, a.id)
    }

    func testVoiceTriggerReusesEmptyChat() {
        let s = makeStore()
        let a = s.newConversation()
        clock += 3600
        XCTAssertEqual(s.forVoiceTrigger().id, a.id)
        XCTAssertEqual(s.conversations.count, 1)
    }

    func testSearchSnippetsFindsEarlierChatsOnly() {
        let s = makeStore()
        let old = s.newConversation()
        say(s, "Write me a backup script with rsync", in: old.id)
        say(s, "Here's `~/bin/backup.sh` using ==rsync -a==.", role: .haku, in: old.id)
        clock += 600
        let other = s.newConversation()
        say(s, "What's the weather", in: other.id)
        clock += 600
        let cur = s.newConversation()
        say(s, "Run that rsync backup again", in: cur.id)

        let r = s.searchSnippets("that rsync backup script", excluding: cur.id)
        XCTAssertTrue(r.contains("backup.sh"), r)
        XCTAssertFalse(r.contains("=="), r)
        XCTAssertFalse(r.contains("Run that rsync backup again"), r)
        XCTAssertFalse(r.contains("weather"), r)
        XCTAssertEqual(s.searchSnippets("zebra", excluding: cur.id), "no earlier chats matched")
    }

    func testSearchSnippetsRespectsCap() {
        let s = makeStore()
        for i in 0..<5 {
            let c = s.newConversation()
            say(s, "deploy notes \(i) " + String(repeating: "deploy details ", count: 40), in: c.id)
            clock += 10
        }
        let r = s.searchSnippets("deploy", excluding: nil, maxChars: 500)
        XCTAssertLessThanOrEqual(r.count, 500)
        XCTAssertFalse(r.isEmpty)
    }
}
