import AppKit
import SwiftUI

/// Five-card permissions flow (Margin-Onboarding) with tally-stroke progress.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    var onDone: () -> Void
    @State private var step = 0
    @State private var mic = Permissions.microphone
    @State private var speech = Permissions.speech
    @State private var ax = Permissions.accessibility
    @State private var axWaiting = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(step + 1) of 5").font(FontFactory.font(theme.type.chrome, size: 13, italic: theme.type.chromeItalic))
                    .foregroundStyle(theme.colors.muted)
                Spacer()
                OnboardingTally(done: step + 1)
            }
            illustration
                .frame(maxWidth: .infinity).frame(height: 112)
                .background(theme.colors.paper2)
                .overlay(Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1))
            title.font(theme.font(.pageTitle)).foregroundStyle(theme.colors.ink).lineHeight(1.15, size: 24)
            copy.font(theme.font(.listItem)).lineHeight(1.5, size: 15).foregroundStyle(theme.colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            footer.frame(maxWidth: .infinity)
        }
        .padding(.top, 34).padding(.horizontal, 22).padding(.bottom, 20)
        .frame(width: 420, height: 560)
        .background(theme.colors.paper)
        .inkText(theme)
        .onAppear {
            let resume = UserDefaults.standard.integer(forKey: "onboarding.resumeStep")
            if resume > 0 { step = resume; UserDefaults.standard.removeObject(forKey: "onboarding.resumeStep") }
        }
        .onReceive(timer) { _ in
            mic = Permissions.microphone
            speech = Permissions.speech
            ax = Permissions.accessibility
        }
    }

    private var hotkey: String { HotkeyManager.display(.holdToTalk) }

    @ViewBuilder private var title: some View {
        switch step {
        case 0: Text("Hello, I'm ") + Text("Haku").italic() + Text(".")
        case 1: Text("Let me hear you")
        case 2: Text("Turn speech into text")
        case 3: Text("Work in any app")
        default: Text("Try it")
        }
    }

    @ViewBuilder private var copy: some View {
        switch step {
        case 0:
            Text("I sit in a corner of your screen and take small jobs: questions, scripts, and handing work to your coding agents. Three permissions and we're done.")
        case 1:
            Text("Only while you hold ") + Text(hotkey).font(theme.font(.mono(13)))
                + Text(", or when a prompt is waiting for a yes or no. Nothing listens in the background.")
        case 2:
            Text("macOS does the transcribing, on this Mac where it can. You can switch to a local Whisper model later in Settings.")
        case 3:
            Text("Accessibility lets the hotkey work everywhere and lets workflows use your selection and the front app. Flip Haku on in System Settings, then come back.")
        default:
            Text("Hold ") + Text(hotkey).font(theme.font(.mono(13))) + Text(" and say ")
                + Text("“what can you do?”").italic().marked(theme) + Text(" or ")
                + Text("“run the tests in devenv”").italic().marked(theme) + Text(".")
        }
    }

    @ViewBuilder private var illustration: some View {
        switch step {
        case 0:
            CardGlyph(color: theme.colors.ink, highlight: theme.highlight, highlightTilt: -3, paperLine: theme.colors.paper).frame(width: 64, height: 64)
        case 1:
            InkIcon(kind: .mic, lineWidth: 1.2).frame(width: 56, height: 56).foregroundStyle(theme.colors.ink)
        case 2:
            HStack(spacing: 10) {
                SquiggleShape(level: 1).stroke(theme.colors.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 42, height: 28)
                Text("→").font(theme.font(.ui)).foregroundStyle(theme.colors.ink)
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle().fill(theme.highlight).frame(width: 40, height: 8)
                    Rectangle().fill(theme.colors.ink).frame(width: 28, height: 1.6)
                }
            }
        case 3:
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 3).stroke(theme.colors.ink, lineWidth: 1.4).frame(width: 70, height: 46)
                    .overlay(alignment: .top) { Rectangle().fill(theme.colors.ink).frame(height: 1.4).padding(.top, 10) }
                    .padding(.trailing, 34).padding(.bottom, 10)
                HStack(spacing: 8) {
                    Capsule().fill(theme.colors.ink).frame(width: 22, height: 1.4)
                    Capsule().fill(ax == .allowed ? theme.colors.ink : theme.colors.rule).frame(width: 14, height: 8)
                }
                .frame(width: 58, height: 28)
                .background(RoundedRectangle(cornerRadius: 2).fill(theme.colors.paper))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(theme.colors.ink, lineWidth: 1.4))
            }
        default:
            VStack(spacing: 10) {
                WidgetView(state: .idle, size: .small)
                Text("drag me anywhere").font(FontFactory.font(theme.type.chrome, size: 12, italic: true)).foregroundStyle(theme.colors.muted)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch step {
            case 0:
                primary("Start") { step = 1 }
            case 1:
                if mic == .allowed {
                    allowed("Microphone allowed")
                    primary("Continue") { step = 2 }
                } else if mic == .denied {
                    Text("Microphone is off for Haku.").textRole(.label, theme).foregroundStyle(theme.colors.muted)
                    primary("Open System Settings") { Permissions.openSettings("Privacy_Microphone") }
                    Button("skip") { step = 2 }.buttonStyle(InkLinkStyle())
                } else {
                    primary("Allow microphone") { Task { _ = await Permissions.requestMicrophone(); mic = Permissions.microphone } }
                }
            case 2:
                if speech == .allowed {
                    allowed("Speech recognition allowed")
                    primary("Continue") { step = 3 }
                } else {
                    primary("Allow speech recognition") {
                        Task { _ = await Permissions.requestSpeech(); speech = Permissions.speech; if speech == .allowed { step = 3 } }
                    }
                    Button("not now") { step = 3 }.buttonStyle(InkLinkStyle())
                }
            case 3:
                if ax == .allowed {
                    allowed("Accessibility allowed")
                    primary("Continue") { step = 4 }
                } else {
                    if axWaiting {
                        Text("waiting for System Settings…").font(FontFactory.font(theme.type.chrome, size: 13, italic: true))
                            .foregroundStyle(theme.colors.muted)
                    }
                    primary("Open System Settings") { axWaiting = true; Permissions.promptAccessibility(); Permissions.openSettings("Privacy_Accessibility") }
                    HStack(spacing: 14) {
                        if axWaiting {
                            Button("already on? relaunch Haku") { Self.relaunch(resumeAt: 3) }.buttonStyle(InkLinkStyle())
                        }
                        Button("not now") { step = 4 }.buttonStyle(InkLinkStyle())
                    }
                }
            default:
                primary("Done", action: onDone)
            }
        }
    }

    /// macOS sometimes only reports a fresh Accessibility grant to a new process.
    static func relaunch(resumeAt step: Int) {
        UserDefaults.standard.set(step, forKey: "onboarding.resumeStep")
        let url = Bundle.main.bundleURL
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; open -n \"\(url.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(FullWidthButtonStyle())
            .keyboardShortcut(.defaultAction)
    }

    private func allowed(_ text: String) -> some View {
        HStack(spacing: 6) {
            SVGShape("M5 12l5 5 9-10", viewBox: CGSize(width: 24, height: 24))
                .stroke(theme.colors.blueInk, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
            Text(text).font(FontFactory.font(theme.type.voice, size: 15, italic: true)).foregroundStyle(theme.colors.blueInk)
        }
    }
}

/// Onboarding `.btn`: full-width filled ink, 38 pt.
struct FullWidthButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.button, theme)
            .foregroundStyle(theme.colors.paper)
            .frame(maxWidth: .infinity).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.ink))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Five tally strokes, 8 pt apart, done = ink.
struct OnboardingTally: View {
    @Environment(\.theme) private var theme
    let done: Int
    var body: some View {
        HStack(spacing: 6.4) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(i < done ? theme.colors.ink : theme.colors.rule).frame(width: 1.6, height: 10)
            }
        }
        .frame(height: 12)
        .accessibilityLabel("Step \(done) of 5")
    }
}
