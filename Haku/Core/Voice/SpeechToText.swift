@preconcurrency import AVFoundation
import Foundation
import Speech
@preconcurrency import WhisperKit

/// One push-to-talk utterance: feed buffers, get partials, finish for the final text.
protocol TranscriptionSession: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async -> String
    func cancel() async
}

enum SpeechEngineFactory {
    /// Picks the engine: on-device SpeechAnalyzer (macOS 26+) when the setting and locale allow, otherwise WhisperKit.
    static func makeSession(engine: STTEngine, locale: Locale, whisper: WhisperEngine,
                            partial: @escaping @Sendable (String) -> Void) async throws -> TranscriptionSession {
        if engine == .onDevice, #available(macOS 26.0, *) {
            if let session = try await AnalyzerSession.make(locale: locale, partial: partial) {
                return session
            }
        }
        return WhisperSession(engine: whisper, language: locale.language.languageCode?.identifier)
    }
}

// MARK: - SpeechAnalyzer (macOS 26+)

@available(macOS 26.0, *)
final class AnalyzerSession: TranscriptionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let converter: BufferConverter
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var resultsTask: Task<String, Never>?
    private let lock = NSLock()

    private init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, format: AVAudioFormat,
                 input: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.converter = BufferConverter(target: format)
        self.input = input
    }

    /// Returns nil when the locale isn't supported on device (caller falls back to Whisper).
    static func make(locale: Locale, partial: @escaping @Sendable (String) -> Void) async throws -> AnalyzerSession? {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.modelUnavailable(supported.identifier)
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let session = AnalyzerSession(analyzer: analyzer, transcriber: transcriber, format: format, input: continuation)
        session.resultsTask = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        partial(finalized)
                    } else {
                        partial(finalized + text)
                    }
                }
            } catch {}
            return finalized
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        return session
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async -> String {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = await resultsTask?.value ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
    }
}

// MARK: - WhisperKit

/// Lazily loads a WhisperKit model once and reuses it.
actor WhisperEngine {
    private var pipe: WhisperKit?
    private var loadedModel: String?
    var model: String = "openai_whisper-base"

    func setModel(_ m: String) { model = m }

    func pipeline() async throws -> WhisperKit {
        if let pipe, loadedModel == model { return pipe }
        do {
            let p = try await WhisperKit(WhisperKitConfig(model: model, verbose: false, logLevel: .none, prewarm: true, load: true, download: true))
            pipe = p
            loadedModel = model
            return p
        } catch {
            throw VoiceError.modelUnavailable(model)
        }
    }

    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard samples.count > 1600 else { return "" }
        nonisolated(unsafe) let p = try await pipeline()
        let options = DecodingOptions(task: .transcribe, language: language, temperature: 0,
                                      detectLanguage: language == nil, skipSpecialTokens: true, withoutTimestamps: true)
        let results: [TranscriptionResult] = try await p.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Accumulates 16 kHz mono samples during the utterance, transcribes on finish.
final class WhisperSession: TranscriptionSession, @unchecked Sendable {
    private let engine: WhisperEngine
    private let language: String?
    private let converter = BufferConverter(target: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!)
    private var samples: [Float] = []
    private let lock = NSLock()

    init(engine: WhisperEngine, language: String?) {
        self.engine = engine
        self.language = language
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let out = converter.convert(buffer), let data = out.floatChannelData else { return }
        let chunk = Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    func finish() async -> String {
        let s = lock.withLock { samples }
        return (try? await engine.transcribe(s, language: language)) ?? ""
    }

    func cancel() async { lock.withLock { samples = [] } }
}
