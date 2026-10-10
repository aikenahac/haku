@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

/// Listens on-device for "Haku". Uses the custom openWakeWord model when it's installed
/// (~/Library/Application Support/Haku/wakeword/), otherwise falls back to on-device speech recognition.
@MainActor
@Observable
final class WakeWordService {
    enum Status: Equatable {
        case off
        case starting
        case listening(engine: String)
        case paused
        case unavailable(String)

        var label: String {
            switch self {
            case .off: "off"
            case .starting: "starting…"
            case .listening(let e): "listening · \(e)"
            case .paused: "paused while you talk"
            case .unavailable(let why): why
            }
        }
    }

    private(set) var status: Status = .off
    /// Called with any words heard right after "Haku" ("Haku, open notes" → "open notes").
    @ObservationIgnored var onWake: (String?) -> Void = { _ in }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var fallback: AnyObject?   // FallbackWakeSession (macOS 26+)
    @ObservationIgnored private var detector: OpenWakeWordDetector?
    @ObservationIgnored private var wantRunning = false
    @ObservationIgnored private var pausedCount = 0
    @ObservationIgnored var sensitivity: Double = 0.5 { didSet { detector?.threshold = Self.threshold(sensitivity) } }
    @ObservationIgnored var locale = Locale(identifier: "en-US")

    static var modelDirectory: URL { AppPaths.support.appendingPathComponent("wakeword", isDirectory: true) }
    static var melURL: URL { modelDirectory.appendingPathComponent("melspectrogram.onnx") }
    static var embeddingURL: URL { modelDirectory.appendingPathComponent("embedding_model.onnx") }
    static var wakeModelURL: URL { modelDirectory.appendingPathComponent("haku.onnx") }

    static var customModelInstalled: Bool {
        [melURL, embeddingURL, wakeModelURL].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Higher sensitivity → lower score threshold.
    nonisolated static func threshold(_ sensitivity: Double) -> Float { Float(0.8 - 0.6 * sensitivity) }

    func start() {
        wantRunning = true
        guard pausedCount == 0 else { status = .paused; return }
        Task { await startEngine() }
    }

    func stop() {
        wantRunning = false
        stopEngine()
        status = .off
    }

    /// Pause while the user talks, Haku speaks, or a prompt listens. Balanced with `resume()`.
    func pause() {
        pausedCount += 1
        guard pausedCount == 1, wantRunning else { return }
        stopEngine()
        status = .paused
    }

    func resume() {
        pausedCount = max(0, pausedCount - 1)
        guard pausedCount == 0, wantRunning else { return }
        Task { await startEngine() }
    }

    private func startEngine() async {
        guard wantRunning, engine == nil, pausedCount == 0 else { return }
        guard Permissions.microphone == .allowed else { status = .unavailable("needs the microphone"); return }
        status = .starting
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = BufferConverter(target: target)
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { status = .unavailable("no microphone"); return }

        var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
        if Self.customModelInstalled {
            do {
                let d = try OpenWakeWordDetector(melURL: Self.melURL, embeddingURL: Self.embeddingURL,
                                                 modelURL: Self.wakeModelURL, threshold: Self.threshold(sensitivity))
                detector = d
                sink = Self.detectorSink(d, converter: converter) { [weak self] in self?.fired(nil) }
                status = .listening(engine: "custom model")
            } catch {
                Log.info("wake model failed to load: \(error)")
            }
        }
        if sink == nil {
            guard #available(macOS 26.0, *) else { status = .unavailable("needs the custom model on this macOS"); return }
            do {
                let f = try await FallbackWakeSession.make(locale: locale) { [weak self] after in
                    Task { @MainActor in self?.fired(after) }
                }
                guard wantRunning, pausedCount == 0 else { await f.cancel(); return }
                fallback = f
                sink = Self.fallbackSink(f)
                status = .listening(engine: "on-device speech")
            } catch {
                status = .unavailable("speech model unavailable")
                return
            }
        }
        guard let sink else { return }
        Self.installTap(on: input, format: format, sink: sink)
        do {
            eng.prepare()
            try eng.start()
            engine = eng
        } catch {
            input.removeTap(onBus: 0)
            status = .unavailable("mic busy")
        }
    }

    nonisolated private static func detectorSink(_ d: OpenWakeWordDetector, converter: BufferConverter,
                                                 onFire: @escaping @MainActor () -> Void) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in
            guard let out = converter.convert(buffer), let data = out.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
            if d.process(samples) { Task { @MainActor in onFire() } }
        }
    }

    @available(macOS 26.0, *)
    nonisolated private static func fallbackSink(_ f: FallbackWakeSession) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in f.append(buffer) }
    }

    /// Built outside the main actor: the tap block runs on the realtime audio thread.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in sink(buffer) }
    }

    private func stopEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        detector = nil
        if #available(macOS 26.0, *), let f = fallback as? FallbackWakeSession {
            Task { await f.cancel() }
        }
        fallback = nil
    }

    private func fired(_ after: String?) {
        guard wantRunning, pausedCount == 0 else { return }
        Log.info("wake word heard\(after.map { " + “\($0)”" } ?? "")")
        detector?.reset()
        onWake(after)
    }
}

/// Fallback detector: continuous on-device transcription, matching "Haku" (and common mishearings).
/// Captures whatever follows in the same breath so "Haku, open notes" works as one utterance.
@available(macOS 26.0, *)
final class FallbackWakeSession: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let converter: BufferConverter
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var task: Task<Void, Never>?

    /// "Haku" as the recognizer tends to write it.
    static let pattern = try! NSRegularExpression(
        pattern: #"\b(?:hey |ok |okay )?(haku|hakoo|hakku|hakuu|hako|hacku|hakou|ha ku|haiku|hockoo)\b[,.!?]?\s*(.*)$"#,
        options: [.caseInsensitive])

    private init(analyzer: SpeechAnalyzer, format: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer
        self.converter = BufferConverter(target: format)
        self.input = input
    }

    static func make(locale: Locale, onWake: @escaping @Sendable (String?) -> Void) async throws -> FallbackWakeSession {
        let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: loc, preset: .progressiveTranscription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await req.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.modelUnavailable(loc.identifier)
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .utility, modelRetention: .whileInUse))
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let s = FallbackWakeSession(analyzer: analyzer, format: format, input: cont)
        s.task = Task {
            var armed: (start: Date, after: String)?
            var lastHit = Date.distantPast
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let range = NSRange(text.startIndex..., in: text)
                    if let m = pattern.firstMatch(in: text, range: range), Date.now.timeIntervalSince(lastHit) > 2 {
                        let after = Range(m.range(at: 2), in: text).map { String(text[$0]) } ?? ""
                        if armed == nil { armed = (.now, after) } else { armed?.after = after }
                        // Wait for the sentence to finish (final result or a pause), then report.
                        if result.isFinal || Date.now.timeIntervalSince(armed!.start) > 2.5 {
                            let words = armed!.after.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                            lastHit = .now
                            armed = nil
                            onWake(words.isEmpty ? nil : words)
                        }
                    } else if let a = armed, result.isFinal || Date.now.timeIntervalSince(a.start) > 2.5 {
                        lastHit = .now
                        armed = nil
                        let words = a.after.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                        onWake(words.isEmpty ? nil : words)
                    }
                }
            } catch {}
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        return s
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        if let c = converter.convert(buffer) { input.yield(AnalyzerInput(buffer: c)) }
    }

    func cancel() async {
        input.finish()
        await analyzer.cancelAndFinishNow()
        task?.cancel()
    }
}
