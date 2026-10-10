import Foundation

/// Runs commands for the shell/script/shortcut tools. Login shell so the user's PATH applies.
enum ShellRunner {
    struct Result: Sendable {
        var exitCode: Int32
        var output: String
        var summary: String {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = trimmed.count > 3000 ? "…" + trimmed.suffix(3000) : trimmed
            return "exit \(exitCode)\n\(tail)"
        }
    }

    static func run(_ command: String, cwd: String? = nil, timeout: TimeInterval = 300) async -> Result {
        await runProcess("/bin/zsh", ["-lc", command], cwd: cwd, timeout: timeout)
    }

    static func runProcess(_ path: String, _ args: [String], cwd: String? = nil, stdin: String? = nil,
                           timeout: TimeInterval = 300) async -> Result {
        await withCheckedContinuation { c in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd.expandingTilde) }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            let input = Pipe()
            p.standardInput = input
            let buffer = OutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { h in buffer.append(h.availableData) }
            p.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
                c.resume(returning: Result(exitCode: proc.terminationStatus, output: buffer.string))
            }
            do {
                try p.run()
                if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
                try? input.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
            } catch {
                c.resume(returning: Result(exitCode: -1, output: error.localizedDescription))
            }
        }
    }

    /// The user's login-shell environment, captured once (PATH for claude/codex/bun…).
    static let loginEnvironment: [String: String] = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", "env -0"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            for entry in data.split(separator: 0) {
                let s = String(decoding: entry, as: UTF8.self)
                if let eq = s.firstIndex(of: "=") { env[String(s[..<eq])] = String(s[s.index(after: eq)...]) }
            }
        } catch {}
        return env
    }()

    /// Resolves a binary name to a path using the login PATH.
    static func which(_ name: String) -> String? {
        if name.contains("/") { return FileManager.default.isExecutableFile(atPath: name.expandingTilde) ? name.expandingTilde : nil }
        let path = loginEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        let extra = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map(\.expandingTilde)
        for dir in path.split(separator: ":").map(String.init) + extra {
            let full = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }
}

final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    private let limit = 2_000_000
    func append(_ d: Data) { lock.withLock { if data.count < limit { data.append(d) } } }
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}

/// Spots destructive or outward-facing commands so the slip can warn about them.
enum CommandRisk {
    struct Consequence: Equatable, Sendable {
        var text: String
        var destructive: Bool
        var listCommand: String?
    }

    static func assess(_ command: String, cwd: String?) async -> [Consequence] {
        var out: [Consequence] = []
        let c = " " + command + " "
        if c.contains(" find ") && c.contains(" -delete") {
            let list = command.replacingOccurrences(of: "-delete", with: "-print")
            let r = await ShellRunner.run(list, cwd: cwd, timeout: 10)
            let n = r.output.split(separator: "\n").filter { !$0.isEmpty }.count
            out.append(Consequence(text: "Permanently deletes \(n) file\(n == 1 ? "" : "s")", destructive: true, listCommand: list))
        } else if c.range(of: #"\srm\s"#, options: .regularExpression) != nil {
            out.append(Consequence(text: "Deletes files", destructive: true))
        }
        if c.contains(" sudo ") { out.append(Consequence(text: "Runs as administrator", destructive: true)) }
        if c.contains("git push") { out.append(Consequence(text: "Pushes to a remote", destructive: true)) }
        if c.contains("git reset --hard") || c.contains("git clean") {
            out.append(Consequence(text: "Discards local changes", destructive: true))
        }
        if c.range(of: #"\s(curl|wget|ssh|scp|rsync|docker (pull|push)|docker compose)"#, options: .regularExpression) != nil {
            out.append(Consequence(text: "touches network", destructive: false))
        }
        return out
    }
}
