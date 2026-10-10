import Foundation
import os

/// Small app log: os_log plus ~/Library/Application Support/Haku/haku.log (text only, rotated at 1 MB).
enum Log {
    private static let logger = Logger(subsystem: "dev.haku.Haku", category: "app")
    private static let queue = DispatchQueue(label: "haku.log")
    private static var url: URL { AppPaths.support.appendingPathComponent("haku.log") }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        queue.async {
            let u = url
            if let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
               (attrs[.size] as? Int ?? 0) > 1_000_000 {
                try? FileManager.default.removeItem(at: u)
            }
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? Data(line.utf8).write(to: u)
            }
        }
    }
}
