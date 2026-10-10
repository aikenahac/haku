import Foundation

enum AppPaths {
    /// ~/Library/Application Support/Haku
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Haku", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// $TMPDIR/Haku/attachments — context files, deleted after use.
    static var attachments: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Haku/attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var history: URL { support.appendingPathComponent("history.json") }
    static var workflows: URL { support.appendingPathComponent("workflows.json") }
    static var tasks: URL { support.appendingPathComponent("tasks.json") }
}

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension String {
    /// `~/code` → `/Users/me/code`
    var expandingTilde: String { (self as NSString).expandingTildeInPath }

    /// `/Users/me/code` → `~/code`
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
