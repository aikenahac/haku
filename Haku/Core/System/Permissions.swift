import AppKit
@preconcurrency import AVFoundation
import ApplicationServices
import Speech

enum PermissionState: Equatable { case notAsked, waiting, allowed, denied }

/// Microphone, speech recognition, accessibility and (optional) screen recording.
enum Permissions {
    static var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var speech: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    static var accessibility: PermissionState { AXIsProcessTrusted() ? .allowed : .notAsked }

    /// Shows the system prompt and opens the Accessibility pane.
    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static var screenRecording: PermissionState { CGPreflightScreenCaptureAccess() ? .allowed : .notAsked }

    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }
}
