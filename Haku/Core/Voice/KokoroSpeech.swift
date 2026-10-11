@preconcurrency import AVFoundation
import FluidAudio
import Observation

/// Kokoro-82M on the Neural Engine (via FluidAudio). English only; the model downloads on first use.
/// Sentences are synthesized one after another while earlier ones play, so a streaming reply starts talking early.
@MainActor
@Observable
final class KokoroSpeech: SpeechOutput {
    enum State: Equatable {
        case notLoaded, loading, ready, failed(String)
        var label: String {
            switch self {
            case .notLoaded: "not downloaded yet"
            case .loading: "downloading voice model…"
            case .ready: "ready"
            case .failed(let e): "unavailable · \(e)"
            }
        }
    }

    private(set) var state: State = .notLoaded

    @ObservationIgnored var voice = KokoroAneConstants.defaultVoice
    /// 0…1, mapped onto Kokoro's speed 0.8…1.2.
    @ObservationIgnored var rate: Double = 0.5
    @ObservationIgnored var onStart: () -> Void = {}
    @ObservationIgnored var onFinish: () -> Void = {}

    /// v3 pins its SourceGenerator to the GPU, and on macOS 27 MPSGraph aborts on its dynamic shapes
    /// ("shape for TensorData is not static"). The legacy pipeline keeps those stages on the CPU there.
    @ObservationIgnored private let manager = KokoroAneManager(
        version: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? .legacy : .v3)
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: Double(KokoroAneConstants.sampleRate), channels: 1)!

    // One utterance at a time: a chain of sentences that ends when the last one has played.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var chain: Task<Void, Never>?
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var listenTap: (@Sendable (AVAudioPCMBuffer) -> Void)?

    static let voices: [String] = KokoroAneConstants.englishVoices.filter { $0.hasPrefix("a") || $0.hasPrefix("b") }

    static func label(for voice: String) -> String {
        let name = voice.split(separator: "_").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? voice
        let accent = voice.hasPrefix("b") ? "British" : "American"
        let kind = voice.dropFirst().first == "m" ? "male" : "female"
        return "\(name) · \(accent) \(kind)"
    }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    var isReady: Bool { state == .ready }
    var isSpeaking: Bool { active }

    /// Downloads (first time) and loads the model. Safe to call repeatedly.
    func prepare() {
        guard loadTask == nil, state != .ready else { return }
        state = .loading
        loadTask = Task {
            do {
                try await manager.initialize(preloadVoices: [voice])
                // A throwaway sentence compiles the remaining stages so the first real reply is quick.
                _ = try await manager.synthesizeDetailed(text: "Hi.", voice: voice)
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
            loadTask = nil
        }
    }

    // MARK: Utterances

    /// Starts an utterance. `listen` receives echo-cancelled mic audio while it plays (for barge-in).
    func begin(listen: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil) {
        stop()
        generation += 1
        active = true
        closed = false
        started = false
        pending = 0
        listenTap = listen
    }

    /// Queues a sentence. Synthesis runs in order, overlapping with playback of earlier sentences.
    func enqueue(_ sentence: String) {
        guard active, !closed else { return }
        let text = SpeechText.clean(sentence)
        guard !text.isEmpty else { return }
        pending += 1
        let gen = generation, prev = chain, voice = voice
        let speed = Float(0.8 + rate * 0.4)
        chain = Task {
            await prev?.value
            guard gen == generation else { return }
            do {
                let r = try await manager.synthesizeDetailed(text: text, voice: voice, speed: speed)
                guard gen == generation else { return }
                play(r.samples, gen: gen)
            } catch {
                guard gen == generation else { return }
                pending -= 1
                checkDone()
            }
        }
    }

    /// No more sentences for this utterance; returns once everything queued has played (or it was stopped).
    func finish() async {
        guard active else { return }
        closed = true
        checkDone()
        guard active else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func speak(_ text: String) async {
        begin()
        var splitter = SentenceSplitter()
        for s in splitter.flush(text) { enqueue(s) }
        await finish()
    }

    func stop() {
        generation += 1
        chain?.cancel()
        chain = nil
        player.stop()
        pending = 0
        if active { end() }
    }

    // MARK: Playback

    private func play(_ samples: [Float], gen: Int) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            pending -= 1
            checkDone()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if !engine.isRunning {
            guard startEngine() else { pending -= 1; checkDone(); return }
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.pending -= 1
                self.checkDone()
            }
        }
        if !player.isPlaying { player.play() }
        if !started { started = true; onStart() }
    }

    /// With a listener, the engine runs voice processing so its mic tap hears the user but not Haku.
    private func startEngine() -> Bool {
        let input = engine.inputNode
        let wantVP = listenTap != nil
        if input.isVoiceProcessingEnabled != wantVP {
            try? input.setVoiceProcessingEnabled(wantVP)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        if let tap = listenTap {
            let f = input.outputFormat(forBus: 0)
            if f.sampleRate > 0 { Self.installTap(on: input, format: f, sink: tap) }
        }
        do {
            try engine.start()
            return true
        } catch {
            if listenTap != nil { input.removeTap(onBus: 0) }
            return false
        }
    }

    /// Built outside the main actor: the tap block runs on the realtime audio thread.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink(buffer) }
    }

    private func checkDone() {
        if active, closed, pending <= 0 { end() }
    }

    private func end() {
        active = false
        if listenTap != nil { engine.inputNode.removeTap(onBus: 0) }
        listenTap = nil
        if engine.isRunning { engine.stop() }
        started = false
        onFinish()
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }
}
