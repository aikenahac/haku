import XCTest
@testable import Haku

final class SentenceSplitterTests: XCTestCase {
    /// Feeds `text` one character at a time, like a token stream, then flushes.
    private func stream(_ text: String) -> [String] {
        var s = SentenceSplitter()
        var out: [String] = []
        var so = ""
        for c in text { so.append(c); out += s.feed(so) }
        return out + s.flush(so)
    }

    func testSplitsStreamingSentences() {
        XCTAssertEqual(stream("The build finished without errors. All forty two tests passed! Want me to push it?"),
                       ["The build finished without errors.", "All forty two tests passed!", "Want me to push it?"])
    }

    func testEmitsBeforeTheStreamEnds() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.feed("The build finished without errors. All for"), ["The build finished without errors."])
        XCTAssertEqual(s.feed("The build finished without errors. All forty two tests passed. "), ["All forty two tests passed."])
    }

    func testJoinsShortSentences() {
        XCTAssertEqual(stream("Sure. I'll open the project for you now."), ["Sure. I'll open the project for you now."])
    }

    func testKeepsAbbreviationsDecimalsAndListNumbers() {
        XCTAssertEqual(stream("Use a light model, e.g. Gemma at 1.5 GB, for routing. Mr. Smith agreed with that plan."),
                       ["Use a light model, e.g. Gemma at 1.5 GB, for routing.", "Mr. Smith agreed with that plan."])
        XCTAssertEqual(stream("Steps:\n1. Open the project folder.\n2. Run the tests."),
                       ["Steps:", "1. Open the project folder.", "2. Run the tests."])
    }

    func testReplacesCodeBlocks() {
        XCTAssertEqual(stream("Here's the fix for that bug.\n```swift\nlet x = 1. y = 2.\n```\nThat should do it for now."),
                       ["Here's the fix for that bug.", SpeechText.codeNote, "That should do it for now."])
    }

    func testRestartedStreamStartsOver() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.feed("Let me check that for you first. "), ["Let me check that for you first."])
        XCTAssertEqual(s.flush("Your calendar is clear tomorrow."), ["Your calendar is clear tomorrow."])
    }

    func testCleanStripsMarkup() {
        XCTAssertEqual(SpeechText.clean("- Saved to `~/haku/notes.md`, see https://example.com/x"),
                       "Saved to home haku/notes.md, see a link")
        XCTAssertEqual(SpeechText.clean("## ==Done== **now**"), "Done now")
    }
}
