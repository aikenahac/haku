import Foundation

/// Makes sure the model a request needs is actually loaded on the local server.
/// LM Studio (incl. the Bionic app) only auto-loads with JIT loading switched on, so Haku loads
/// models itself: REST load endpoint first, then the `lms` CLI. It can also start the server.
actor ModelManager {
    struct Config: Sendable {
        var endpoint: String
        var apiKey: String
        var serverType: ServerType
        var lmsPath: String
    }

    private var config: Config
    private var resolved: [String: String] = [:]   // configured id → server key
    private var loading: [String: Task<String, Error>] = [:]

    init(config: Config) { self.config = config }

    func update(_ c: Config) {
        if c.endpoint != config.endpoint { resolved = [:] }
        config = c
    }

    private var client: OpenAIClient { OpenAIClient(endpoint: config.endpoint, apiKey: config.apiKey) }

    /// Base URL without the `/v1` suffix (for LM Studio's native API).
    private var root: URL {
        var s = config.endpoint.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") { s.removeLast(3) }
        return URL(string: s) ?? URL(string: "http://localhost:1234")!
    }

    /// Returns the server's key for `model`, loading it first if needed. `ttl` (seconds) lets the
    /// server unload it again when idle (used for the on-demand escalation model).
    func ensureLoaded(_ model: String, ttl: Int? = nil) async throws -> String {
        guard config.serverType == .lmStudio else { return model }
        if let t = loading[model] { return try await t.value }
        let task = Task<String, Error> { try await self.load(model, ttl: ttl) }
        loading[model] = task
        defer { loading[model] = nil }
        return try await task.value
    }

    private func load(_ model: String, ttl: Int?) async throws -> String {
        if !(await serverUp()) {
            Log.info("model server down; trying lms server start")
            _ = await lms(["server", "start"], timeout: 30)
            for _ in 0..<20 where !(await serverUp()) { try await Task.sleep(for: .milliseconds(500)) }
            guard await serverUp() else { throw LLMError.unreachable("LM Studio server isn't running") }
        }
        let models = await nativeModels()
        let key = Self.resolve(model, among: models.map(\.key) + ((try? await client.models()) ?? [])) ?? model
        resolved[model] = key
        if models.first(where: { $0.key == key })?.loaded == true { return key }
        if models.isEmpty, (try? await client.models())?.contains(key) == true, await isLoadedViaPS(key) { return key }

        Log.info("loading model \(key)")
        if await restLoad(key, ttl: ttl) { return key }
        var args = ["load", key, "--yes"]
        if let ttl { args += ["--ttl", String(ttl)] }
        let r = await lms(args, timeout: 300)
        guard r.exitCode == 0 else {
            throw LLMError.http(400, "couldn't load \(key): \(r.output.split(separator: "\n").last ?? "")")
        }
        return key
    }

    /// The configured id resolved to the server's key (after the first load).
    func key(for model: String) -> String { resolved[model] ?? model }

    // MARK: Server probes

    private func serverUp() async -> Bool {
        var r = URLRequest(url: root.appendingPathComponent("v1/models"))
        r.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    struct NativeModel: Sendable { var key: String; var loaded: Bool }

    /// LM Studio's native model list (`/api/v1/models`, falling back to `/api/v0/models`).
    private func nativeModels() async -> [NativeModel] {
        for path in ["api/v1/models", "api/v0/models"] {
            var r = URLRequest(url: root.appendingPathComponent(path))
            r.timeoutInterval = 3
            if !config.apiKey.isEmpty { r.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
            guard let (data, resp) = try? await URLSession.shared.data(for: r),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = JSONValue.parse(String(decoding: data, as: UTF8.self)) else { continue }
            let list = json["data"]?.arrayValue ?? json["models"]?.arrayValue ?? json.arrayValue ?? []
            let out = list.compactMap { m -> NativeModel? in
                guard let key = m["key"]?.stringValue ?? m["id"]?.stringValue ?? m["model_key"]?.stringValue else { return nil }
                if let type = m["type"]?.stringValue, type == "embeddings" || type == "embedding" { return nil }
                let state = m["state"]?.stringValue
                let instances = m["loaded_instances"]?.arrayValue ?? []
                return NativeModel(key: key, loaded: state == "loaded" || !instances.isEmpty)
            }
            if !out.isEmpty { return out }
        }
        return []
    }

    private func restLoad(_ key: String, ttl: Int?) async -> Bool {
        var body: [String: JSONValue] = ["model": .string(key)]
        if let ttl { body["ttl"] = .number(Double(ttl)) }
        var r = URLRequest(url: root.appendingPathComponent("api/v1/models/load"))
        r.httpMethod = "POST"
        r.timeoutInterval = 300
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty { r.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try? JSONEncoder().encode(JSONValue.object(body))
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func isLoadedViaPS(_ key: String) async -> Bool {
        let r = await lms(["ps"], timeout: 10)
        return r.exitCode == 0 && r.output.contains(key)
    }

    // MARK: lms CLI

    nonisolated static func findLMS(configured: String) -> String? {
        let candidates = [configured, "~/.lmstudio/bin/lms", "~/.lmstudio/apps/bionic/bin/lms", "~/.cache/lm-studio/bin/lms"]
            .filter { !$0.isEmpty }.map(\.expandingTilde)
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ShellRunner.which("lms")
    }

    private func lms(_ args: [String], timeout: TimeInterval) async -> ShellRunner.Result {
        guard let path = Self.findLMS(configured: config.lmsPath) else {
            return ShellRunner.Result(exitCode: -1, output: "lms CLI not found")
        }
        return await ShellRunner.runProcess(path, args, timeout: timeout)
    }

    // MARK: Name matching

    /// "gemma-4-e4b" → "google/gemma-4-e4b-it-mlx" etc. Exact match wins, then containment, then token overlap.
    nonisolated static func resolve(_ wanted: String, among keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let w = norm(wanted)
        if let exact = keys.first(where: { $0 == wanted || norm($0) == w }) { return exact }
        let tail = keys.filter { norm($0.split(separator: "/").last.map(String.init) ?? $0).hasPrefix(w) }
        if let best = tail.min(by: { $0.count < $1.count }) { return best }
        if let contains = keys.filter({ norm($0).contains(w) }).min(by: { $0.count < $1.count }) { return contains }
        let tokens = Set(wanted.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let scored = keys.map { k -> (String, Int) in
            let kt = Set(k.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (k, tokens.intersection(kt).count)
        }.filter { $0.1 >= max(2, tokens.count - 1) }
        return scored.max { $0.1 < $1.1 }?.0
    }
}
