import AppKit
import ScreenCaptureKit
import ServiceManagement
import UserNotifications

@MainActor
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, id: String = UUID().uuidString) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}

enum Screenshot {
    /// Captures the main display (needs Screen Recording; only this feature does).
    static func captureMainDisplay() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.showsCursor = false
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cg, size: NSSize(width: display.width, height: display.height))
    }
}

enum Terminal {
    /// Opens Terminal running `command` in `dir` (via a temporary .command file; no Apple Events needed).
    static func open(dir: String, command: String? = nil) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("haku-\(UUID().uuidString.prefix(8)).command")
        let quoted = "'" + dir.expandingTilde.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let body = "#!/bin/zsh -l\ncd \(quoted)\n\(command ?? "")\nexec $SHELL -l\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
