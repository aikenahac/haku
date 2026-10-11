@preconcurrency import AVFoundation
import Foundation
import NaturalLanguage
import Observation

/// mic → STT → (Brain) → TTS, with barge-in. Owns the audio session for one utterance at a time.
@MainActor
@Observable
final class VoicePipeline {
    enum Phase: Equatable { case idle, preparing, listening, transcribing, speaking }

    private(set) var phase: Phase = .idle
    private(set) var level: Double = 0
    private(set) var partial: String = ""
    private(set) var listeningSince: Date?

    @ObservationIgnored let speech = SystemSpeech()
    let kokoro = KokoroSpeech()
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let bargeIn = BargeInMonitor()
    @ObservationIgnored private var session: TranscriptionSession?
    @ObservationIgnored let whisper = WhisperEngine()
    @ObservationIgnored private var startTask: Task<Void, Error>?
    @ObservationIgnored private var pendingStop = false
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var reply: SpokenReply?
    @ObservationIgnored private var speakingID: UUID?

    /// A reply being spoken while it streams in. The engine is picked on its first sentence.
    private struct SpokenReply {
        let id: UUID
        let bargeIn: Bool
        var splitter = SentenceSplitter()
        var useKokoro: Bool?
    }

    init(settings: AppSettings) {
        self.settings = settings
        let started: () -> Void = { [weak self] in self?.phase = .speaking }
        let finished: () -> Void = { [weak self] in
            guard let self else { return }
            if self.phase == .speaking { self.phase = .idle }
            self.bargeIn.stop()
        }
        speech.onStart = started
        speech.onFinish = finished
        kokoro.onStart = started
        kokoro.onFinish = finished
        prepareVoice()
    }

    /// Loads the Kokoro model in the background when it's the chosen engine.
    func prepareVoice() {
        if settings.ttsEngine == .kokoro { kokoro.prepare() }
    }

    var isListening: Bool { phase == .listening || phase == .preparing }

    /// Opens the mic. Speaking is interrupted (barge-in).
    func beginListening(locale: Locale? = nil) async throws {
        stopSpeaking()
        guard !isListening else { return }
        switch Permissions.microphone {
        case .notAsked:
            guard await Permissions.requestMicrophone() else { throw VoiceError.micDenied }
        case .denied, .waiting:
            throw VoiceError.micDenied
        case .allowed:
            break
        }
        phase = .preparing
        partial = ""
        level = 0
        pendingStop = false
        listeningSince = .now
        let engine = settings.sttEngine
        let loc = locale ?? settings.primaryLocale
        await whisper.setModel(settings.whisperModel)
        do {
            let s = try await SpeechEngineFactory.makeSession(engine: engine, locale: loc, whisper: whisper) { [weak self] text in
                Task { @MainActor in self?.partial = text }
            }
            session = s
            try capture.start(sink: { buffer in s.append(buffer) },
                              level: { [weak self] v in Task { @MainActor in self?.level = v } })
            phase = .listening
        } catch {
            phase = .idle
            listeningSince = nil
            await session?.cancel()
            session = nil
            throw error
        }
    }

    /// Closes the mic and returns the final transcript.
    func endListening() async -> String {
        guard let s = session else { phase = .idle; return "" }
        capture.stop()
        phase = .transcribing
        level = 0
        let text = await s.finish()
        session = nil
        listeningSince = nil
        if phase == .transcribing { phase = .idle }
        return text.isEmpty ? partial.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }

    func cancelListening() {
        capture.stop()
        let s = session
        session = nil
        Task { await s?.cancel() }
        phase = .idle
        level = 0
        listeningSince = nil
    }

    /// Speaks a reply. While speaking, loud speech from the user stops it (voice-processed mic, echo-cancelled).
    func speak(_ text: String, allowVoiceBargeIn: Bool) async {
        let id = beginSpokenReply(allowVoiceBargeIn: allowVoiceBargeIn)
        await endSpokenReply(id, finalText: text)
    }

    // MARK: Streaming replies

    /// Starts speaking a reply that's still being written. Feed it with `appendReplyText`, close with `endSpokenReply`.
    func beginSpokenReply(allowVoiceBargeIn: Bool) -> UUID {
        stopSpeaking()
        let id = UUID()
        reply = SpokenReply(id: id, bargeIn: allowVoiceBargeIn && Permissions.microphone == .allowed)
        speakingID = id
        return id
    }

    /// The whole reply so far; finished sentences start playing (Kokoro only — the system voice waits for the end).
    func appendReplyText(_ id: UUID, _ text: String) {
        guard reply?.id == id, let chunks = reply?.splitter.feed(text) else { return }
        route(chunks)
    }

    /// Speaks whatever is left and returns when Haku has finished talking (or was interrupted).
    func endSpokenReply(_ id: UUID, finalText: String) async {
        guard reply?.id == id, let rest = reply?.splitter.flush(finalText) else { return }
        route(rest)
        let r = reply!
        reply = nil
        if r.useKokoro == true {
            await kokoro.finish()
            return
        }
        var splitter = SentenceSplitter()
        let text = splitter.flush(finalText).joined(separator: " ")
        guard speakingID == id, !text.isEmpty else { return }
        speech.voiceIdentifier = settings.voiceIdentifier
        speech.rate = settings.speechRate
        if r.bargeIn {
            bargeIn.start { [weak self] in Task { @MainActor in self?.stopSpeaking() } }
        }
        await speech.speak(text)
        bargeIn.stop()
    }

    /// Stops this reply's speech if it's still the current one (the turn was cancelled or failed).
    func cancelSpokenReply(_ id: UUID) {
        if speakingID == id { stopSpeaking() }
    }

    private func route(_ sentences: [String]) {
        guard var r = reply, !sentences.isEmpty else { return }
        if r.useKokoro == nil {
            let use = wantsKokoro(for: sentences.joined(separator: " "))
            r.useKokoro = use
            if use {
                kokoro.voice = settings.kokoroVoice
                kokoro.rate = settings.speechRate
                let listen = r.bargeIn ? BargeInMonitor.detector { [weak self] in Task { @MainActor in self?.stopSpeaking() } } : nil
                kokoro.begin(listen: listen)
            }
            reply = r
        }
        if r.useKokoro == true { sentences.forEach(kokoro.enqueue) }
    }

    /// Kokoro speaks English; anything else (or a model that isn't loaded yet) goes to the system voice.
    private func wantsKokoro(for text: String) -> Bool {
        guard settings.ttsEngine == .kokoro else { return false }
        guard kokoro.isReady else { kokoro.prepare(); return false }
        let langs = settings.languages.map { String($0.prefix(2)) }
        if langs.allSatisfy({ $0 == "en" }) { return true }
        let rec = NLLanguageRecognizer()
        rec.languageConstraints = Set(langs).map { NLLanguage(rawValue: $0) }
        rec.processString(text)
        return rec.dominantLanguage == .english
    }

    func stopSpeaking() {
        bargeIn.stop()
        reply = nil
        speakingID = nil
        if kokoro.isSpeaking { kokoro.stop() }
        if speech.isSpeaking || phase == .speaking { speech.stop() }
        if phase == .speaking { phase = .idle }
    }
}

/// Detects the user talking over Haku. Uses voice processing (AEC) so Haku's own voice doesn't trigger it.
final class BargeInMonitor: @unchecked Sendable {
    private var engine: AVAudioEngine?

    /// Mic buffers in, `onSpeech` out once enough loud frames arrive in a row.
    static func detector(onSpeech: @escaping @Sendable () -> Void) -> @Sendable (AVAudioPCMBuffer) -> Void {
        final class Counter: @unchecked Sendable { var loud = 0 }
        let counter = Counter(), threshold: Float = 0.06, needed = 10
        return { buffer in
            guard let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[0][i] * data[0][i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            counter.loud = rms > threshold ? counter.loud + 1 : max(0, counter.loud - 1)
            if counter.loud >= needed {
                counter.loud = 0
                onSpeech()
            }
        }
    }

    func start(onSpeech: @escaping @Sendable () -> Void) {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        let detect = Self.detector(onSpeech: onSpeech)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in detect(buffer) }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}
