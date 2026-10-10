@preconcurrency import AVFoundation
import Foundation
import OnnxRuntimeBindings

/// Something that hears "Haku" in a stream of 16 kHz mono audio.
protocol WakeWordDetector: AnyObject, Sendable {
    /// Feed 16 kHz mono float samples (−1…1). Returns true when the wake word fired.
    func process(_ samples: [Float]) -> Bool
    func reset()
    var name: String { get }
}

/// openWakeWord runtime: melspectrogram.onnx → embedding_model.onnx → <wakeword>.onnx,
/// following openWakeWord's streaming AudioFeatures (80 ms frames, 76-frame embedding windows).
final class OpenWakeWordDetector: WakeWordDetector, @unchecked Sendable {
    let name: String
    private let env: ORTEnv
    private let mel: ORTSession
    private let embed: ORTSession
    private let classifier: ORTSession
    private let melInput: String, embedInput: String, clsInput: String
    private let featureFrames: Int
    var threshold: Float
    /// Frames to stay quiet after a detection (≈2 s).
    private let refractory = 25

    private var raw: [Float] = []          // int16-scaled samples
    private var pending: [Float] = []
    private var melFrames: [[Float]] = []  // each 32 bins
    private var features: [[Float]] = []   // each 96
    private var cooldown = 0
    private let lock = NSLock()

    static let chunk = 1280                // 80 ms at 16 kHz

    init(melURL: URL, embeddingURL: URL, modelURL: URL, threshold: Float = 0.5) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(1)
        mel = try ORTSession(env: env, modelPath: melURL.path, sessionOptions: opts)
        embed = try ORTSession(env: env, modelPath: embeddingURL.path, sessionOptions: opts)
        classifier = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
        melInput = try mel.inputNames().first ?? "input"
        embedInput = try embed.inputNames().first ?? "input_1"
        clsInput = try classifier.inputNames().first ?? "input"
        featureFrames = 16
        self.threshold = threshold
        name = modelURL.deletingPathExtension().lastPathComponent
    }

    func reset() {
        lock.withLock { raw = []; pending = []; melFrames = []; features = []; cooldown = 0 }
    }

    func process(_ samples: [Float]) -> Bool {
        lock.withLock {
            pending.append(contentsOf: samples.map { $0 * 32767 })
            var fired = false
            while pending.count >= Self.chunk {
                let chunk = Array(pending.prefix(Self.chunk))
                pending.removeFirst(Self.chunk)
                if step(chunk) { fired = true }
            }
            return fired
        }
    }

    /// One 80 ms step: new mel frames → one new embedding → classifier score.
    private func step(_ chunk: [Float]) -> Bool {
        raw.append(contentsOf: chunk)
        if raw.count > 16_000 * 10 { raw.removeFirst(raw.count - 16_000 * 10) }
        // Mel over the new chunk plus 3 hops of context (as openWakeWord does).
        let window = Array(raw.suffix(Self.chunk + 160 * 3))
        guard let spec = try? runMel(window) else { return false }
        melFrames.append(contentsOf: spec)
        if melFrames.count > 970 { melFrames.removeFirst(melFrames.count - 970) }
        guard melFrames.count >= 76, let emb = try? runEmbedding(Array(melFrames.suffix(76))) else { return false }
        features.append(emb)
        if features.count > 120 { features.removeFirst(features.count - 120) }
        if cooldown > 0 { cooldown -= 1; return false }
        guard features.count >= featureFrames, let score = try? runClassifier(Array(features.suffix(featureFrames))) else { return false }
        if score >= threshold {
            cooldown = refractory
            return true
        }
        return false
    }

    private func tensor(_ values: [Float], shape: [Int]) throws -> ORTValue {
        var v = values
        let data = NSMutableData(bytes: &v, length: v.count * MemoryLayout<Float>.size)
        return try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
    }

    private func floats(_ value: ORTValue) throws -> [Float] {
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func runMel(_ audio: [Float]) throws -> [[Float]] {
        let out = try mel.run(withInputs: [melInput: tensor(audio, shape: [1, audio.count])],
                              outputNames: Set(try mel.outputNames()), runOptions: nil)
        guard let v = out.values.first else { return [] }
        let flat = try floats(v).map { $0 / 10 + 2 }
        return stride(from: 0, to: flat.count - 31, by: 32).map { Array(flat[$0..<$0 + 32]) }
    }

    private func runEmbedding(_ frames: [[Float]]) throws -> [Float] {
        let out = try embed.run(withInputs: [embedInput: tensor(frames.flatMap { $0 }, shape: [1, 76, 32, 1])],
                                outputNames: Set(try embed.outputNames()), runOptions: nil)
        guard let v = out.values.first else { return [] }
        return try floats(v)
    }

    private func runClassifier(_ feats: [[Float]]) throws -> Float {
        let out = try classifier.run(withInputs: [clsInput: tensor(feats.flatMap { $0 }, shape: [1, featureFrames, 96])],
                                     outputNames: Set(try classifier.outputNames()), runOptions: nil)
        guard let v = out.values.first else { return 0 }
        return try floats(v).first ?? 0
    }
}
