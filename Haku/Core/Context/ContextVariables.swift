import AppKit
import ApplicationServices

/// Fills workflow template variables. Reads only the selection, front app and clipboard (no window contents).
@MainActor
enum ContextVariables {
    static func expand(_ template: String, after: String) -> String {
        var out = template
        if out.contains("{after}") { out = out.replacingOccurrences(of: "{after}", with: after) }
        if out.contains("{clipboard}") { out = out.replacingOccurrences(of: "{clipboard}", with: clipboard ?? "") }
        if out.contains("{selection}") { out = out.replacingOccurrences(of: "{selection}", with: selection ?? "") }
        if out.contains("{front app}") { out = out.replacingOccurrences(of: "{front app}", with: frontApp ?? "") }
        if out.contains("{date}") {
            out = out.replacingOccurrences(of: "{date}", with: Date.now.formatted(date: .complete, time: .shortened))
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var clipboard: String? { NSPasteboard.general.string(forType: .string) }

    /// The app the user was in before Haku (Haku never activates itself for the widget).
    static var frontApp: String? {
        let app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return lastExternalApp }
        return app?.localizedName
    }

    nonisolated(unsafe) static var lastExternalApp: String?

    /// Selected text in the focused element of the front app (needs Accessibility).
    static var selection: String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
