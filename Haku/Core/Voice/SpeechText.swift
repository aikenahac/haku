import Foundation

/// Turns reply text into what the voice should say.
enum SpeechText {
    static let codeNote = "I've put the code in the chat."

    /// Strips markup the voice shouldn't read out.
    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "==", with: "")
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = t.replacingOccurrences(of: "~/", with: "home ")
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "a link", options: .regularExpression)
        // Headings, bullets and list numbers at line starts.
        t = t.replacingOccurrences(of: #"(?m)^\s*(#{1,6}|[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Cuts a reply that's still streaming into sentences the voice can start on.
/// Feed it the whole text so far each time; it returns only the newly finished pieces.
/// Fenced code blocks are swapped for a short note.
struct SentenceSplitter {
    /// Shorter sentences are held back and joined with the next one, so speech doesn't sound choppy.
    var minLength = 20

    private var said = ""        // the prefix already handed out
    private var inCode = false

    private static let abbreviations: Set<String> = ["e.g", "i.e", "mr", "mrs", "ms", "dr", "vs", "st", "approx", "fig"]
    private static let closers: Set<Character> = ["\"", "'", ")", "”", "’", "]"]

    /// New finished sentences in `text`.
    mutating func feed(_ text: String) -> [String] { split(text, final: false) }

    /// Everything left in `text`, including an unfinished last sentence.
    mutating func flush(_ text: String) -> [String] { split(text, final: true) }

    private mutating func split(_ raw: String, final: Bool) -> [String] {
        let text = String(raw.drop { $0.isWhitespace })
        // A reply that restarted (a tool round, a hand-off to the bigger model) is a fresh stream.
        if !text.hasPrefix(said) { said = ""; inCode = false }
        let rest = Array(text.dropFirst(said.count))
        var out: [String] = []
        var start = 0, i = 0, done = 0

        func emit(_ end: Int) {
            let s = String(rest[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            start = end
            done = end
        }
        func isFence(_ j: Int) -> Bool { j + 2 < rest.count && rest[j] == "`" && rest[j + 1] == "`" && rest[j + 2] == "`" }

        while i < rest.count {
            if inCode {
                if isFence(i) { inCode = false; i += 3; start = i; done = i; continue }
                // Hold back a possible half-written fence.
                if rest[i] != "`" { done = i + 1; start = done }
                i += 1
                continue
            }
            if rest[i] == "`" && !final && rest.count - i < 3 { break }   // might become a fence
            if isFence(i) {
                emit(i)
                out.append(SpeechText.codeNote)
                inCode = true
                i += 3; start = i; done = i
                continue
            }
            let c = rest[i]
            if c == "\n" {
                // Line breaks are real pauses: list items, paragraphs, a colon introducing a list.
                emit(i + 1)
            } else if c == "." || c == "!" || c == "?" {
                var j = i + 1
                while j < rest.count, Self.closers.contains(rest[j]) { j += 1 }
                guard j < rest.count else { if final { i += 1; continue } else { break } }
                if rest[j].isWhitespace, c != "." || isSentenceDot(at: i, in: rest, from: start),
                   rest[start..<j].count >= minLength || rest[j].isNewline {
                    emit(j)
                    i = j
                    continue
                }
            }
            i += 1
        }
        if final {
            if !inCode { emit(rest.count) }
            said = ""; inCode = false
        } else {
            said += String(rest[0..<done])
        }
        return out
    }

    /// False for "e.g.", "Mr.", initials like "J." and list numbers like "2.".
    private func isSentenceDot(at i: Int, in s: [Character], from start: Int) -> Bool {
        var k = i
        while k > start, !s[k - 1].isWhitespace { k -= 1 }
        let word = String(s[k..<i])
        if Self.abbreviations.contains(word.lowercased()) { return false }
        if word.count == 1, word.first!.isUppercase { return false }
        if !word.isEmpty, word.allSatisfy(\.isNumber), s[start..<k].allSatisfy(\.isWhitespace) { return false }
        return true
    }
}
