@preconcurrency import AVFoundation
import Foundation
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
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let bargeIn = BargeInMonitor()
    @ObservationIgnored private var session: TranscriptionSession?
    @ObservationIgnored let whisper = WhisperEngine()
    @ObservationIgnored private var startTask: Task<Void, Error>?
    @ObservationIgnored private var pendingStop = false
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        speech.onStart = { [weak self] in self?.phase = .speaking }
        speech.onFinish = { [weak self] in
            guard let self else { return }
            if self.phase == .speaking { self.phase = .idle }
            self.bargeIn.stop()
        }
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
        speech.voiceIdentifier = settings.voiceIdentifier
        speech.rate = settings.speechRate
        if allowVoiceBargeIn, Permissions.microphone == .allowed {
            bargeIn.start { [weak self] in Task { @MainActor in self?.stopSpeaking() } }
        }
        await speech.speak(text)
        bargeIn.stop()
    }

    func stopSpeaking() {
        bargeIn.stop()
        if speech.isSpeaking || phase == .speaking { speech.stop() }
        if phase == .speaking { phase = .idle }
    }
}

/// Detects the user talking over Haku. Uses voice processing (AEC) so Haku's own voice doesn't trigger it.
final class BargeInMonitor: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var loudFrames = 0
    private let threshold: Float = 0.06
    private let needed = 10

    func start(onSpeech: @escaping @Sendable () -> Void) {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        loudFrames = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[0][i] * data[0][i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            self.loudFrames = rms > self.threshold ? self.loudFrames + 1 : max(0, self.loudFrames - 1)
            if self.loudFrames >= self.needed {
                self.loudFrames = 0
                onSpeech()
            }
        }
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
