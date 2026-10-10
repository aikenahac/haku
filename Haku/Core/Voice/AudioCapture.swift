@preconcurrency import AVFoundation
import Foundation

/// Microphone capture with a live level meter. Buffers are handed to a sink on the audio thread.
final class AudioCapture: @unchecked Sendable {
    typealias BufferSink = @Sendable (AVAudioPCMBuffer) -> Void

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var sink: BufferSink?
    private var levelHandler: (@Sendable (Double) -> Void)?
    private(set) var isRunning = false
    private var smoothed: Double = 0

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    /// Starts the mic. `level` is called ~20×/s with 0…1 (speech-ish loudness).
    func start(sink: @escaping BufferSink, level: @escaping @Sendable (Double) -> Void) throws {
        stop()
        lock.withLock { self.sink = sink; self.levelHandler = level; smoothed = 0 }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.micUnavailable }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw VoiceError.micUnavailable
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.withLock { sink = nil; levelHandler = nil }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let (s, l) = lock.withLock { (sink, levelHandler) }
        s?(buffer)
        guard let l, let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        let ch = data[0]
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrt(sum / Float(n))
        // −50 dB … −10 dB → 0 … 1
        let db = 20 * log10(max(rms, 1e-7))
        let v = Double(min(1, max(0, (db + 50) / 40)))
        let out: Double = lock.withLock {
            smoothed = v > smoothed ? v : smoothed * 0.85 + v * 0.15
            return smoothed
        }
        l(out)
    }
}

enum VoiceError: LocalizedError {
    case micUnavailable
    case micDenied
    case speechDenied
    case localeUnsupported(String)
    case modelUnavailable(String)

    var errorDescription: String? { widgetReason }

    var widgetReason: String {
        switch self {
        case .micUnavailable: "mic unavailable"
        case .micDenied: "mic not allowed"
        case .speechDenied: "speech not allowed"
        case .localeUnsupported: "language unsupported"
        case .modelUnavailable: "speech model missing"
        }
    }
}

/// Converts captured buffers into a target format (sample rate / channels).
final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    let target: AVAudioFormat

    init(target: AVAudioFormat) { self.target = target }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}
