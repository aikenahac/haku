import Foundation
import Observation

enum ServerType: String, CaseIterable, Codable, Sendable, Identifiable {
    case lmStudio, ollama, openAI
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lmStudio: "LM Studio"
        case .ollama: "Ollama"
        case .openAI: "OpenAI-style"
        }
    }
    var defaultEndpoint: String {
        switch self {
        case .lmStudio: "http://localhost:1234/v1"
        case .ollama: "http://localhost:11434/v1"
        case .openAI: "http://localhost:8080/v1"
        }
    }
}

enum FallbackPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case tellMe, useEscalation
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tellMe: "Tell me, don't fall back"
        case .useEscalation: "Fall back to the escalation model"
        }
    }
}

enum AgentKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var displayName: String { self == .claude ? "Claude Code" : "Codex" }
    var shortName: String { self == .claude ? "CC" : "CX" }
    var defaultBinary: String { self == .claude ? "claude" : "codex" }
}

/// Agent edit permissions (Confirm › Edits segment).
enum EditPermission: String, CaseIterable, Codable, Sendable, Identifiable {
    case readOnly, askFirst, allowed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .readOnly: "Read only"
        case .askFirst: "Ask first"
        case .allowed: "Allowed"
        }
    }
    var shortLabel: String {
        switch self {
        case .readOnly: "read only"
        case .askFirst: "ask first"
        case .allowed: "allowed"
        }
    }
    var sentence: String {
        switch self {
        case .readOnly: "Read only, no file edits"
        case .askFirst: "Ask before editing files"
        case .allowed: "Edits allowed"
        }
    }
}

enum STTEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case onDevice, whisper
    var id: String { rawValue }
    var label: String { self == .onDevice ? "macOS, on device" : "Whisper, local" }
}

enum SpeakReplies: String, CaseIterable, Codable, Sendable, Identifiable {
    case always, whenISpoke, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: "Always"
        case .whenISpoke: "When I spoke"
        case .never: "Never"
        }
    }
}

struct AgentConfig: Codable, Equatable, Sendable {
    var binaryPath: String
    var enabled: Bool
    var defaultEdits: EditPermission
}

/// Every non-appearance setting from HANDOFF › Settings, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    // Models
    var serverType: ServerType { didSet { save() } }
    var endpoint: String { didSet { save() } }
    var routingModel: String { didSet { save() } }
    var escalationModel: String { didSet { save() } }
    var fallback: FallbackPolicy { didSet { save() } }
    var apiKey: String { didSet { save() } }

    // Agents
    var claude: AgentConfig { didSet { save() } }
    var codex: AgentConfig { didSet { save() } }
    var defaultFolder: String { didSet { save() } }
    var maxConcurrentJobs: Int { didSet { save() } }

    // Voice
    var sttEngine: STTEngine { didSet { save() } }
    var languages: [String] { didSet { save() } }
    var speakReplies: SpeakReplies { didSet { save() } }
    var voiceIdentifier: String { didSet { save() } }
    var speechRate: Double { didSet { save() } }
    var confirmByVoice: Bool { didSet { save() } }
    var whisperModel: String { didSet { save() } }
    var wakeWordEnabled: Bool { didSet { save() } }
    var wakeSensitivity: Double { didSet { save() } }

    // General
    var onboardingDone: Bool { didSet { save() } }
    var showWidget: Bool { didSet { save() } }
    var keepHistory: Bool { didSet { save() } }

    private struct Stored: Codable {
        var serverType: ServerType = .lmStudio
        var endpoint = ServerType.lmStudio.defaultEndpoint
        var routingModel = "gemma-4-e4b"
        var escalationModel = "qwen3.8-27b"
        var fallback: FallbackPolicy = .tellMe
        var apiKey = ""
        var claude = AgentConfig(binaryPath: "", enabled: true, defaultEdits: .askFirst)
        var codex = AgentConfig(binaryPath: "", enabled: true, defaultEdits: .readOnly)
        var defaultFolder = "~/code"
        var maxConcurrentJobs = 2
        var sttEngine: STTEngine = .onDevice
        var languages = ["en-US"]
        var speakReplies: SpeakReplies = .whenISpoke
        var voiceIdentifier = ""
        var speechRate = 0.5
        var confirmByVoice = true
        var whisperModel = "openai_whisper-base"
        var wakeWordEnabled = true
        var wakeSensitivity = 0.5
        var onboardingDone = false
        var showWidget = true
        var keepHistory = true
    }

    private static let key = "haku.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var s = Stored()
        if let data = defaults.data(forKey: Self.key) {
            // Decode leniently: unknown/missing keys fall back to defaults.
            if let decoded = try? JSONDecoder().decode(PartialStored.self, from: data) { decoded.apply(to: &s) }
        }
        serverType = s.serverType; endpoint = s.endpoint; routingModel = s.routingModel
        escalationModel = s.escalationModel; fallback = s.fallback; apiKey = s.apiKey
        claude = s.claude; codex = s.codex; defaultFolder = s.defaultFolder; maxConcurrentJobs = s.maxConcurrentJobs
        sttEngine = s.sttEngine; languages = s.languages; speakReplies = s.speakReplies
        voiceIdentifier = s.voiceIdentifier; speechRate = s.speechRate; confirmByVoice = s.confirmByVoice
        whisperModel = s.whisperModel; wakeWordEnabled = s.wakeWordEnabled; wakeSensitivity = s.wakeSensitivity
        onboardingDone = s.onboardingDone; showWidget = s.showWidget; keepHistory = s.keepHistory
    }

    func agent(_ kind: AgentKind) -> AgentConfig { kind == .claude ? claude : codex }

    func setAgent(_ kind: AgentKind, _ config: AgentConfig) {
        if kind == .claude { claude = config } else { codex = config }
    }

    var defaultFolderURL: URL { URL(fileURLWithPath: (defaultFolder as NSString).expandingTildeInPath) }

    var primaryLocale: Locale { Locale(identifier: languages.first ?? "en-US") }

    private func save() {
        let s = Stored(serverType: serverType, endpoint: endpoint, routingModel: routingModel,
                       escalationModel: escalationModel, fallback: fallback, apiKey: apiKey,
                       claude: claude, codex: codex, defaultFolder: defaultFolder,
                       maxConcurrentJobs: maxConcurrentJobs, sttEngine: sttEngine, languages: languages,
                       speakReplies: speakReplies, voiceIdentifier: voiceIdentifier, speechRate: speechRate,
                       confirmByVoice: confirmByVoice, whisperModel: whisperModel, wakeWordEnabled: wakeWordEnabled, wakeSensitivity: wakeSensitivity,
                       onboardingDone: onboardingDone, showWidget: showWidget, keepHistory: keepHistory)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: Self.key) }
    }

    /// Every field optional so new settings don't wipe old ones.
    private struct PartialStored: Decodable {
        var serverType: ServerType?; var endpoint: String?; var routingModel: String?; var escalationModel: String?
        var fallback: FallbackPolicy?; var apiKey: String?; var claude: AgentConfig?; var codex: AgentConfig?
        var defaultFolder: String?; var maxConcurrentJobs: Int?; var sttEngine: STTEngine?; var languages: [String]?
        var speakReplies: SpeakReplies?; var voiceIdentifier: String?; var speechRate: Double?; var confirmByVoice: Bool?
        var whisperModel: String?; var wakeWordEnabled: Bool?; var wakeSensitivity: Double?; var onboardingDone: Bool?; var showWidget: Bool?
        var keepHistory: Bool?

        func apply(to s: inout Stored) {
            if let v = serverType { s.serverType = v }; if let v = endpoint { s.endpoint = v }
            if let v = routingModel { s.routingModel = v }; if let v = escalationModel { s.escalationModel = v }
            if let v = fallback { s.fallback = v }; if let v = apiKey { s.apiKey = v }
            if let v = claude { s.claude = v }; if let v = codex { s.codex = v }
            if let v = defaultFolder { s.defaultFolder = v }; if let v = maxConcurrentJobs { s.maxConcurrentJobs = v }
            if let v = sttEngine { s.sttEngine = v }; if let v = languages { s.languages = v }
            if let v = speakReplies { s.speakReplies = v }; if let v = voiceIdentifier { s.voiceIdentifier = v }
            if let v = speechRate { s.speechRate = v }; if let v = confirmByVoice { s.confirmByVoice = v }
            if let v = whisperModel { s.whisperModel = v }; if let v = wakeWordEnabled { s.wakeWordEnabled = v }
            if let v = wakeSensitivity { s.wakeSensitivity = v }
            if let v = onboardingDone { s.onboardingDone = v }; if let v = showWidget { s.showWidget = v }
            if let v = keepHistory { s.keepHistory = v }
        }
    }
}
