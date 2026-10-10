import XCTest
@testable import Haku

/// Serves canned responses for OpenAIClient tests.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body) = Self.handler?(request) ?? (404, "")
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OpenAIClientTests: XCTestCase {
    private func client() -> OpenAIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        var c = OpenAIClient(endpoint: "http://localhost:1234/v1/")
        c.session = URLSession(configuration: cfg)
        return c
    }

    func testStreamsContentAndToolCalls() async throws {
        StubProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/chat/completions")
            let lines = [
                #"{"choices":[{"delta":{"content":"Hel"}}]}"#,
                #"{"choices":[{"delta":{"content":"lo"}}]}"#,
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"open_app","arguments":"{\"na"}}]}}]}"#,
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"me\":\"Safari\"}"}}]},"finish_reason":"tool_calls"}]}"#,
            ]
            return (200, lines.map { "data: \($0)\n\n" }.joined() + "data: [DONE]\n\n")
        }
        var text = ""
        var calls: [LLMToolCall] = []
        for try await ev in client().streamChat(model: "m", messages: [.user("hi")], tools: []) {
            switch ev {
            case .content(let s): text += s
            case .toolCalls(let c): calls = c
            case .done: break
            }
        }
        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].function.name, "open_app")
        XCTAssertEqual(calls[0].args["name"]?.stringValue, "Safari")
    }

    func testHTTPErrorSurfaces() async {
        StubProtocol.handler = { _ in (500, "boom") }
        do {
            for try await _ in client().streamChat(model: "m", messages: [.user("hi")]) {}
            XCTFail("expected error")
        } catch let e as LLMError {
            if case .http(let code, _) = e { XCTAssertEqual(code, 500) } else { XCTFail("\(e)") }
        } catch { XCTFail("\(error)") }
    }

    func testModels() async throws {
        StubProtocol.handler = { _ in (200, #"{"data":[{"id":"gemma-4-e4b"},{"id":"qwen3.8-27b"}]}"#) }
        let ids = try await client().models()
        XCTAssertEqual(ids, ["gemma-4-e4b", "qwen3.8-27b"])
    }

    func testThinkFilter() {
        var f = ThinkFilter()
        let out = f.feed("A<thi") + f.feed("nk>secret</th") + f.feed("ink>B")
        XCTAssertEqual(out, "AB")
    }
}

final class AgentParserTests: XCTestCase {
    func testClaudeStream() {
        let init_ = #"{"type":"system","subtype":"init","session_id":"s-1"}"#
        XCTAssertEqual(ClaudeStreamParser.parse(init_), [.session("s-1")])

        let todo = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"Read files","status":"completed"},{"content":"Run bun test","status":"in_progress"},{"content":"Summarize","status":"pending"}]}}]}}"#
        guard case .steps(let steps) = ClaudeStreamParser.parse(todo).first else { return XCTFail() }
        XCTAssertEqual(steps.map(\.state), [.done, .now, .todo])

        let bash = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bun test"}}]}}"#
        XCTAssertEqual(ClaudeStreamParser.parse(bash), [.log("$ bun test", .command)])

        let result = #"{"type":"tool_result"}"#
        XCTAssertTrue(ClaudeStreamParser.parse(result).isEmpty)

        let out = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"✓ a.spec\n✗ b.spec"}]}}"#
        XCTAssertEqual(ClaudeStreamParser.parse(out), [.log("✓ a.spec", .ok), .log("✗ b.spec", .fail)])

        let done = #"{"type":"result","subtype":"success","is_error":false,"result":"3 failing in compose.spec","session_id":"s-1"}"#
        XCTAssertEqual(ClaudeStreamParser.parse(done).first, .result(text: "3 failing in compose.spec", isError: false))
    }

    func testCodexStream() {
        XCTAssertEqual(CodexStreamParser.parse(#"{"type":"thread.started","thread_id":"t1"}"#), [.session("t1")])
        let cmd = #"{"type":"item.started","item":{"type":"command_execution","command":"ls"}}"#
        XCTAssertEqual(CodexStreamParser.parse(cmd), [.log("$ ls", .command)])
        let msg = #"{"type":"item.completed","item":{"type":"agent_message","text":"All good"}}"#
        XCTAssertEqual(CodexStreamParser.parse(msg).last, .result(text: "All good", isError: false))
        let todo = #"{"type":"item.updated","item":{"type":"todo_list","items":[{"text":"a","completed":true},{"text":"b","completed":false}]}}"#
        guard case .steps(let s) = CodexStreamParser.parse(todo).first else { return XCTFail() }
        XCTAssertEqual(s.map(\.state), [.done, .now])
    }

    func testClaudeArgumentsRespectPermissions() async {
        let settings = await AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let store = await TaskStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).json"))
        let runner = await AgentRunner(store: store, settings: settings)
        let ro = AgentJob(runner: .claude, title: "t", prompt: "run tests", spokenAsk: "", directory: "~", permission: .readOnly)
        let args = await runner.arguments(for: ro)
        XCTAssertTrue(args.contains("--disallowedTools"))
        XCTAssertFalse(args.contains("acceptEdits"))
        let ok = AgentJob(runner: .claude, title: "t", prompt: "fix", spokenAsk: "", directory: "~", permission: .allowed)
        let args2 = await runner.arguments(for: ok)
        XCTAssertTrue(args2.contains("acceptEdits"))
        let cx = AgentJob(runner: .codex, title: "t", prompt: "x", spokenAsk: "", directory: "~", permission: .readOnly)
        let a3 = await runner.arguments(for: cx)
        XCTAssertEqual(a3[a3.firstIndex(of: "--sandbox")! + 1], "read-only")
    }
}

@MainActor
final class WorkflowTests: XCTestCase {
    func testMatchWithAfter() {
        let store = WorkflowStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID()).json"))
        store.upsert(Workflow(name: "Deploy staging", phrases: ["deploy staging", "ship it to staging"], action: .agent, template: "Deploy {after}"))
        let m = store.match("Deploy staging and skip the tests.")
        XCTAssertEqual(m?.0.name, "Deploy staging")
        XCTAssertEqual(m?.1, "skip the tests")
        XCTAssertNil(store.match("please deploy production"))
        XCTAssertEqual(store.match("Ship it to staging")?.1, "")
    }

    func testExpandVariables() {
        let out = ContextVariables.expand("Do {after} now", after: "the thing")
        XCTAssertEqual(out, "Do the thing now")
    }

    func testSpokenConfirmation() async {
        let c = ConfirmationCenter()
        let task = Task { await c.ask(ConfirmationRequest(kind: .shell(command: "ls", cwd: nil), source: "s", question: "q")) }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(c.handleSpoken("hmm what"))
        XCTAssertFalse(c.handleSpoken("okay so anyway the thing is yes"), "background talk must not approve")
        XCTAssertNil(ConfirmationCenter.classify("I guess yes maybe"))
        XCTAssertTrue(c.handleSpoken("Yes, go ahead."))
        let d = await task.value
        XCTAssertTrue(d.approved)

        let t2 = Task { await c.ask(ConfirmationRequest(kind: .shell(command: "ls", cwd: nil), source: "s", question: "q")) }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(c.handleSpoken("No, don't."))
        let d2 = await t2.value
        XCTAssertFalse(d2.approved)
    }

    func testMessageSpanParse() {
        XCTAssertEqual(MessageSpan.parse("the ==A record== in `~/x`."),
                       [.text("the "), .mark("A record"), .text(" in "), .path("~/x"), .text(".")])
    }

    func testCommandRisk() async {
        let r = await CommandRisk.assess("rm -rf build && git push", cwd: nil)
        XCTAssertTrue(r.contains { $0.text == "Deletes files" })
        XCTAssertTrue(r.contains { $0.text == "Pushes to a remote" })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("risk-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<3 { FileManager.default.createFile(atPath: dir.appendingPathComponent("\(i).dmg").path, contents: Data()) }
        let f = await CommandRisk.assess("find \(dir.path) -name '*.dmg' -delete", cwd: nil)
        XCTAssertEqual(f.first?.text, "Permanently deletes 3 files")
        XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: dir.path).count, 3, "preview must not delete")
    }
}
