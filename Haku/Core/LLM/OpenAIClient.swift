import Foundation

/// Arbitrary JSON, for tool schemas and tool arguments.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): String(b)
        default: nil
        }
    }

    var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct LLMToolCall: Codable, Equatable, Sendable {
    struct Function: Codable, Equatable, Sendable {
        var name: String
        var arguments: String
    }
    var id: String
    var type: String = "function"
    var function: Function

    var args: JSONValue { JSONValue.parse(function.arguments) ?? .object([:]) }
}

struct LLMMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String?
    var tool_calls: [LLMToolCall]?
    var tool_call_id: String?
    var name: String?

    static func system(_ s: String) -> LLMMessage { LLMMessage(role: "system", content: s) }
    static func user(_ s: String) -> LLMMessage { LLMMessage(role: "user", content: s) }
    static func assistant(_ s: String?, tools: [LLMToolCall]? = nil) -> LLMMessage {
        LLMMessage(role: "assistant", content: s, tool_calls: tools)
    }
    static func tool(_ id: String, name: String, _ s: String) -> LLMMessage {
        LLMMessage(role: "tool", content: s, tool_call_id: id, name: name)
    }
}

struct LLMTool: Encodable, Sendable {
    struct Function: Encodable, Sendable {
        var name: String
        var description: String
        var parameters: JSONValue
    }
    var type = "function"
    var function: Function

    init(_ name: String, _ description: String, properties: [String: JSONValue], required: [String]) {
        function = Function(name: name, description: description, parameters: .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ]))
    }

    static func prop(_ type: String, _ description: String, enum values: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string(type), "description": .string(description)]
        if let values { o["enum"] = .array(values.map(JSONValue.string)) }
        if type == "array" { o["items"] = .object(["type": .string("string")]) }
        return .object(o)
    }
}

enum LLMStreamEvent: Sendable {
    case content(String)
    case toolCalls([LLMToolCall])
    case done(finishReason: String?)
}

enum LLMError: LocalizedError {
    case unreachable(String)
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unreachable(let s): "model server unreachable (\(s))"
        case .http(let code, let body): "model server error \(code): \(body.prefix(200))"
        case .badResponse: "unexpected response from the model server"
        }
    }

    /// Short reason for the widget error state.
    var widgetReason: String {
        switch self {
        case .unreachable: "model offline"
        case .http: "model error"
        case .badResponse: "model error"
        }
    }
}

/// Minimal OpenAI-compatible client (LM Studio, Ollama, llama.cpp…): streaming chat + tool calls.
struct OpenAIClient: Sendable {
    var endpoint: URL
    var apiKey: String?
    var session: URLSession = .shared

    init(endpoint: String, apiKey: String? = nil) {
        var e = endpoint.trimmingCharacters(in: .whitespaces)
        while e.hasSuffix("/") { e.removeLast() }
        self.endpoint = URL(string: e) ?? URL(string: "http://localhost:1234/v1")!
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 120) -> URLRequest {
        var r = URLRequest(url: endpoint.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = timeout
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        r.httpBody = body
        return r
    }

    func models() async throws -> [String] {
        struct Resp: Decodable { struct M: Decodable { var id: String }; var data: [M] }
        do {
            let (data, resp) = try await session.data(for: request("models", timeout: 3))
            guard let http = resp as? HTTPURLResponse else { throw LLMError.badResponse }
            guard http.statusCode == 200 else { throw LLMError.http(http.statusCode, String(decoding: data, as: UTF8.self)) }
            return try JSONDecoder().decode(Resp.self, from: data).data.map(\.id)
        } catch let e as LLMError {
            throw e
        } catch {
            throw LLMError.unreachable(error.localizedDescription)
        }
    }

    struct ChatBody: Encodable {
        var model: String
        var messages: [LLMMessage]
        var tools: [LLMTool]?
        var tool_choice: String?
        var stream: Bool
        var temperature: Double
        var max_tokens: Int?
    }

    /// Streams a chat completion. Content deltas arrive as they're generated; accumulated
    /// tool calls arrive once at the end.
    func streamChat(model: String, messages: [LLMMessage], tools: [LLMTool]? = nil,
                    temperature: Double = 0.4, maxTokens: Int? = nil) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let body = ChatBody(model: model, messages: messages, tools: tools?.isEmpty == false ? tools : nil,
                            tool_choice: tools?.isEmpty == false ? "auto" : nil, stream: true,
                            temperature: temperature, max_tokens: maxTokens)
        let req = request("chat/completions", method: "POST", body: try? JSONEncoder().encode(body), timeout: 300)
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else { throw LLMError.badResponse }
                    if http.statusCode != 200 {
                        var text = ""
                        for try await line in bytes.lines { text += line; if text.count > 2000 { break } }
                        throw LLMError.http(http.statusCode, text)
                    }
                    var acc = ToolCallAccumulator()
                    var thinking = ThinkFilter()
                    var finish: String?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8)),
                              let choice = chunk.choices.first else { continue }
                        if let c = choice.delta.content, !c.isEmpty {
                            let visible = thinking.feed(c)
                            if !visible.isEmpty { continuation.yield(.content(visible)) }
                        }
                        for tc in choice.delta.tool_calls ?? [] { acc.add(tc) }
                        if let f = choice.finish_reason { finish = f }
                    }
                    let calls = acc.calls
                    if !calls.isEmpty { continuation.yield(.toolCalls(calls)) }
                    continuation.yield(.done(finishReason: finish))
                    continuation.finish()
                } catch let e as LLMError {
                    continuation.finish(throwing: e)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let e as URLError where e.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: LLMError.unreachable(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Non-streaming convenience: returns the final text.
    func complete(model: String, messages: [LLMMessage], temperature: Double = 0.3, maxTokens: Int? = nil) async throws -> String {
        var out = ""
        for try await ev in streamChat(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens) {
            if case .content(let s) = ev { out += s }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Wire types

    struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
                var tool_calls: [ToolCallDelta]?
            }
            var delta: Delta
            var finish_reason: String?
        }
        var choices: [Choice]
    }

    struct ToolCallDelta: Decodable {
        struct F: Decodable { var name: String?; var arguments: String? }
        var index: Int?
        var id: String?
        var function: F?
    }

    struct ToolCallAccumulator {
        private var byIndex: [Int: (id: String, name: String, args: String)] = [:]
        private var order: [Int] = []

        mutating func add(_ d: ToolCallDelta) {
            let i = d.index ?? (d.id != nil ? order.count : max(0, order.count - 1))
            if byIndex[i] == nil { byIndex[i] = (d.id ?? "call_\(i)", "", ""); order.append(i) }
            if let id = d.id, !id.isEmpty { byIndex[i]!.id = id }
            if let n = d.function?.name { byIndex[i]!.name += n }
            if let a = d.function?.arguments { byIndex[i]!.args += a }
        }

        var calls: [LLMToolCall] {
            order.compactMap { i in
                guard let c = byIndex[i], !c.name.isEmpty else { return nil }
                return LLMToolCall(id: c.id, function: .init(name: c.name, arguments: c.args.isEmpty ? "{}" : c.args))
            }
        }
    }
}

/// Drops `<think>…</think>` reasoning blocks (Qwen) from streamed content.
struct ThinkFilter {
    private var inThink = false
    private var pending = ""

    mutating func feed(_ s: String) -> String {
        pending += s
        var out = ""
        while !pending.isEmpty {
            if inThink {
                if let r = pending.range(of: "</think>") {
                    pending = String(pending[r.upperBound...]); inThink = false
                } else {
                    // Keep a tail in case the closing tag is split across chunks.
                    pending = String(pending.suffix(8)); return out
                }
            } else {
                if let r = pending.range(of: "<think>") {
                    out += pending[..<r.lowerBound]; pending = String(pending[r.upperBound...]); inThink = true
                } else if let lt = pending.lastIndex(of: "<"), "<think>".hasPrefix(pending[lt...]) {
                    out += pending[..<lt]; pending = String(pending[lt...]); return out
                } else {
                    out += pending; pending = ""
                }
            }
        }
        return out
    }
}
