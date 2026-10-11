@preconcurrency import AVFoundation
import NaturalLanguage

/// Speech output: `SystemSpeech` (AVSpeechSynthesizer) or `KokoroSpeech`.
@MainActor
protocol SpeechOutput: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String) async
    func stop()
}

@MainActor
final class SystemSpeech: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    var voiceIdentifier: String = ""
    /// 0…1, mapped onto AVSpeechUtterance's min…max.
    var rate: Double = 0.5
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func speak(_ text: String) async {
        stop()
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }
        let u = AVSpeechUtterance(string: clean)
        u.voice = voice(for: clean)
        let min = Double(AVSpeechUtteranceMinimumSpeechRate), max = Double(AVSpeechUtteranceMaximumSpeechRate)
        u.rate = Float(min + (max - min) * (0.25 + rate * 0.5))
        onStart()
        await withCheckedContinuation { c in
            continuation = c
            synth.speak(u)
        }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        resume()
    }

    private func resume() {
        let c = continuation
        continuation = nil
        if c != nil { onFinish() }
        c?.resume()
    }

    private func voice(for text: String) -> AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            // Respect the chosen voice unless the reply is clearly in another language.
            let lang = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
            if lang == nil || v.language.hasPrefix(lang!) { return v }
        }
        let lang = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Strips markup the voice shouldn't read out.
    static func speakable(_ text: String) -> String { SpeechText.clean(text) }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") || $0.language.hasPrefix("sl") }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
