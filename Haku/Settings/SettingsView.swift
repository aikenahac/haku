import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", models = "Models & agents", hotkeys = "Hotkeys & voice", appearance = "Appearance", about = "About"
    var id: String { rawValue }
}

/// Settings window (Margin-Settings): 160 pt nav + form sections.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.embeddedInMainWindow) private var embedded
    @Bindable var state: SettingsSectionState
    var showWorkflows: () -> Void
    var showOnboarding: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(theme.font(.widgetState(20))).foregroundStyle(theme.colors.ink)
                    .padding(.horizontal, 10).padding(.bottom, 14)
                ForEach(SettingsSection.allCases) { s in
                    Button { state.section = s } label: {
                        Text(s.rawValue).font(theme.font(.listItem))
                            .foregroundStyle(state.section == s ? theme.colors.ink : theme.colors.muted)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radii.button).fill(state.section == s ? theme.colors.paper2 : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !embedded {
                    Button { NSApp.keyWindow?.performClose(nil) } label: { Text("close").font(theme.font(.link(13))) }
                        .buttonStyle(InkLinkStyle(size: 13))
                        .keyboardShortcut("w", modifiers: .command)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 18).padding(.horizontal, 10)
            .frame(width: 160)
            .padding(.top, embedded ? 26 : 10)
            VRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch state.section {
                    case .general: GeneralSettings(showWorkflows: showWorkflows, showOnboarding: showOnboarding)
                    case .models: ModelSettings()
                    case .hotkeys: HotkeySettings()
                    case .appearance: AppearanceSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.horizontal, 26).padding(.vertical, 22).padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.colors.paper)
        .inkText(theme)
    }
}

// MARK: - Building blocks

/// `.h`: serif italic 18 with a rule underneath.
struct SectionHeading: View {
    @Environment(\.theme) private var theme
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).textRole(.heading, theme).foregroundStyle(theme.colors.ink)
            HRule()
        }
        .padding(.top, 6)
    }
}

/// `.f`: 104 pt label column + control.
struct FormRow<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label).textRole(.label, theme).foregroundStyle(theme.colors.muted)
                .frame(width: 104, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FormStack<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 10) { content } }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    var showWorkflows: () -> Void
    var showOnboarding: () -> Void
    @State private var loginItem = LoginItem.isEnabled
    @State private var tick = 0

    var body: some View {
        @Bindable var settings = settings
        SectionHeading(title: "General")
        FormStack {
            FormRow(label: "Open at login") {
                InkSwitch(isOn: Binding(get: { loginItem }, set: { loginItem = $0; LoginItem.set($0) }))
            }
            FormRow(label: "Show widget") { InkSwitch(isOn: $settings.showWidget) }
            FormRow(label: "Show in Dock") {
                HStack(spacing: 10) {
                    InkSwitch(isOn: $settings.showInDock)
                    Text("off = menu bar and widget only").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                }
            }
            FormRow(label: "Keep history") {
                HStack(spacing: 10) {
                    InkSwitch(isOn: $settings.keepHistory)
                    Text("text only; attachments are deleted after each task").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                    Button("delete all chats") { model.clearConversation() }.buttonStyle(InkLinkStyle(size: 13, color: theme.colors.error))
                }
            }
            FormRow(label: "Workflows") {
                HStack(spacing: 10) {
                    Text("\(model.workflows.workflows.count) saved").textRole(.ui, theme).foregroundStyle(theme.colors.ink)
                    Button("edit") { showWorkflows() }.buttonStyle(InkLinkStyle(size: 13))
                }
            }
        }
        SectionHeading(title: "Permissions")
        FormStack {
            permissionRow("Microphone", Permissions.microphone, pane: "Privacy_Microphone")
            permissionRow("Speech", Permissions.speech, pane: "Privacy_SpeechRecognition")
            permissionRow("Accessibility", Permissions.accessibility, pane: "Privacy_Accessibility")
            permissionRow("Screen Recording", Permissions.screenRecording, pane: "Privacy_ScreenCapture", optional: true)
            FormRow(label: "") {
                Button("Run the welcome steps again") { showOnboarding() }.buttonStyle(InkLinkStyle(size: 13))
            }
        }
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    private func permissionRow(_ name: String, _ state: PermissionState, pane: String, optional: Bool = false) -> some View {
        FormRow(label: name) {
            HStack(spacing: 10) {
                Text(state == .allowed ? "allowed" : optional ? "off · only needed for screenshot attach" : "not allowed")
                    .font(FontFactory.font(theme.type.voice, size: 13, italic: true))
                    .foregroundStyle(state == .allowed ? theme.colors.blueInk : theme.colors.muted)
                if state != .allowed {
                    Button("open System Settings") { Permissions.openSettings(pane) }.buttonStyle(InkLinkStyle(size: 13))
                }
            }
        }
    }
}

// MARK: - Models & agents

struct ModelSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var editing: AgentKind?

    var body: some View {
        @Bindable var settings = settings
        SectionHeading(title: "Local model")
        FormStack {
            FormRow(label: "Server") {
                InkSegmented(options: ServerType.allCases, selection: Binding(get: { settings.serverType }, set: { t in
                    if settings.endpoint == settings.serverType.defaultEndpoint { settings.endpoint = t.defaultEndpoint }
                    settings.serverType = t
                    Task { await model.refreshModelStatus() }
                })) { $0.label }
            }
            FormRow(label: "Endpoint") {
                HStack(spacing: 10) {
                    InkTextField(text: $settings.endpoint).onSubmit { Task { await model.refreshModelStatus() } }
                    Text(model.modelOnline == true ? "connected" : model.modelOnline == false ? "offline" : "checking…")
                        .font(FontFactory.font(theme.type.voice, size: 13, italic: true))
                        .foregroundStyle(model.modelOnline == false ? theme.colors.error : theme.colors.blueInk)
                    Button("check") { Task { await model.refreshModelStatus() } }.buttonStyle(InkLinkStyle(size: 13))
                }
            }
            FormRow(label: "Model") {
                InkPicker(options: modelOptions(settings.routingModel), selection: $settings.routingModel) { $0 }
            }
            FormRow(label: "Harder questions") {
                InkPicker(options: modelOptions(settings.escalationModel), selection: $settings.escalationModel) { $0 }
            }
            FormRow(label: "If it's down") {
                InkPicker(options: FallbackPolicy.allCases, selection: $settings.fallback) { $0.label }
            }
            if settings.serverType == .lmStudio {
                FormRow(label: "lms CLI") {
                    HStack(spacing: 10) {
                        let found = ModelManager.findLMS(configured: settings.lmsPath)
                        InkTextField(placeholder: found?.abbreviatingHome ?? "not found", text: $settings.lmsPath)
                        Text(found == nil ? "needed to load models on demand" : "loads models on demand")
                            .font(FontFactory.font(theme.type.voice, size: 13, italic: true))
                            .foregroundStyle(found == nil ? theme.colors.error : theme.colors.blueInk)
                            .fixedSize()
                    }
                }
            }
            if settings.serverType == .openAI {
                FormRow(label: "API key") { InkTextField(placeholder: "optional", text: $settings.apiKey) }
            }
        }
        SectionHeading(title: "Agents")
        VStack(spacing: 0) {
            ForEach(AgentKind.allCases) { kind in agentRow(kind) }
        }
        FormStack {
            FormRow(label: "Default folder") {
                HStack(spacing: 10) {
                    InkTextField(text: $settings.defaultFolder)
                    Button("choose") { chooseFolder() }.buttonStyle(InkLinkStyle(size: 13))
                }
            }
            FormRow(label: "Run at most") {
                InkSegmented(options: [1, 2, 4], selection: $settings.maxConcurrentJobs) { "\($0)" }.frame(maxWidth: 200)
            }
        }
    }

    private func modelOptions(_ current: String) -> [String] {
        var opts = model.availableModels
        if !opts.contains(current) { opts.insert(current, at: 0) }
        return opts
    }

    @ViewBuilder private func agentRow(_ kind: AgentKind) -> some View {
        let config = settings.agent(kind)
        let resolved = ShellRunner.which(config.binaryPath.isEmpty ? kind.defaultBinary : config.binaryPath)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.displayName).font(theme.font(.body(16))).foregroundStyle(theme.colors.ink)
                Spacer()
                InkSwitch(isOn: Binding(get: { config.enabled }, set: { v in var c = config; c.enabled = v; settings.setAgent(kind, c) }))
            }
            HStack {
                Text("\(resolved?.abbreviatingHome ?? "not found") · edits: \(config.defaultEdits.shortLabel)")
                    .font(theme.font(.mono(11.5)))
                    .foregroundStyle(resolved == nil ? theme.colors.error : theme.colors.muted)
                Spacer()
                Button(editing == kind ? "done" : "edit") { editing = editing == kind ? nil : kind }.buttonStyle(InkLinkStyle())
            }
            if editing == kind {
                FormStack {
                    FormRow(label: "Binary") {
                        InkTextField(placeholder: kind.defaultBinary,
                                     text: Binding(get: { config.binaryPath }, set: { v in var c = config; c.binaryPath = v; settings.setAgent(kind, c) }))
                    }
                    FormRow(label: "Edits") {
                        InkSegmented(options: EditPermission.allCases,
                                     selection: Binding(get: { config.defaultEdits }, set: { v in var c = config; c.defaultEdits = v; settings.setAgent(kind, c) })) { $0.label }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { HRule() }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = settings.defaultFolderURL
        if p.runModal() == .OK, let u = p.url { settings.defaultFolder = u.path.abbreviatingHome }
    }
}

// MARK: - Hotkeys & voice

struct HotkeySettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var recording: KeyboardShortcuts.Name?
    @State private var tick = 0

    static let languageOptions: [(String, String)] = [
        ("en-US", "English"), ("en-GB", "English (UK)"), ("sl-SI", "Slovenščina"), ("de-DE", "Deutsch"),
        ("hr-HR", "Hrvatski"), ("it-IT", "Italiano"), ("fr-FR", "Français"), ("es-ES", "Español"),
    ]

    var body: some View {
        @Bindable var settings = settings
        SectionHeading(title: "Hotkeys")
        FormStack {
            hotkeyRow("Hold to talk", .holdToTalk)
            hotkeyRow("Open panel", .openPanel)
            hotkeyRow("Tasks", .showTasks)
            FormRow(label: "Stop / deny") { KeyCap(text: "esc") }
            FormRow(label: "Approve") {
                HStack(spacing: 6) {
                    KeyCap(text: "⏎")
                    Text("only while a prompt is open").font(FontFactory.font(theme.type.chrome, size: 12.5, italic: theme.type.chromeItalic))
                        .foregroundStyle(theme.colors.muted).padding(.leading, 6)
                }
            }
        }
        .id(tick)
        SectionHeading(title: "Voice")
        FormStack {
            FormRow(label: "Speech to text") {
                InkSegmented(options: STTEngine.allCases, selection: $settings.sttEngine) { $0.label }
            }
            if settings.sttEngine == .whisper {
                FormRow(label: "Whisper model") {
                    InkPicker(options: ["openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small", "openai_whisper-large-v3-v20240930_turbo"],
                              selection: $settings.whisperModel) { $0.replacingOccurrences(of: "openai_whisper-", with: "") }
                }
            }
            FormRow(label: "Languages") {
                HStack(spacing: 6) {
                    ForEach(settings.languages, id: \.self) { code in
                        Button { if settings.languages.count > 1 { settings.languages.removeAll { $0 == code } } } label: {
                            Text(Self.languageOptions.first { $0.0 == code }?.1 ?? code)
                                .font(FontFactory.font(theme.type.ui, size: 11.5, weight: .medium))
                                .foregroundStyle(theme.colors.ink)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.paper2))
                                .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(settings.languages.first == code ? "Primary language · click to remove" : "Click to remove")
                    }
                    Menu {
                        ForEach(Self.languageOptions.filter { !settings.languages.contains($0.0) }, id: \.0) { code, name in
                            Button(name) { settings.languages.append(code) }
                        }
                    } label: { Text("+ add").font(theme.font(.link(14))).foregroundStyle(theme.colors.blueInk).underline() }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            FormRow(label: "Speak replies") {
                InkSegmented(options: SpeakReplies.allCases, selection: $settings.speakReplies) { $0.label }
            }
            FormRow(label: "Engine") {
                InkSegmented(options: TTSEngine.allCases, selection: $settings.ttsEngine) { $0.label }
                    .onChange(of: settings.ttsEngine) { model.voice.prepareVoice() }
            }
            FormRow(label: "Voice") {
                HStack(spacing: 10) {
                    if settings.ttsEngine == .kokoro {
                        InkPicker(options: KokoroSpeech.voices, selection: $settings.kokoroVoice) { KokoroSpeech.label(for: $0) }
                    } else {
                        InkPicker(options: [""] + SystemSpeech.availableVoices.map(\.identifier), selection: $settings.voiceIdentifier) { id in
                            id.isEmpty ? "[system voice]" : (AVSpeechSynthesisVoice(identifier: id).map { "\($0.name) · \($0.language)" } ?? id)
                        }
                    }
                    Button("preview") {
                        Task { await model.voice.speak("Hi, I'm Haku. Hold the hotkey and tell me what you need.", allowVoiceBargeIn: false) }
                    }
                    .buttonStyle(InkLinkStyle())
                }
            }
            if settings.ttsEngine == .kokoro, !model.voice.kokoro.isReady {
                FormRow(label: "") {
                    Text("Kokoro \(model.voice.kokoro.state.label) · the macOS voice speaks until it's ready")
                        .textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                }
            }
            FormRow(label: "Rate") {
                Slider(value: $settings.speechRate, in: 0...1).tint(theme.colors.ink)
            }
            FormRow(label: "Listen for “Haku”") {
                HStack(spacing: 10) {
                    InkSwitch(isOn: $settings.wakeWordEnabled)
                    Text(settings.wakeWordEnabled ? model.wake.status.label : "off · only the hotkey opens the mic")
                        .textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                }
            }
            if settings.wakeWordEnabled {
                FormRow(label: "Sensitivity") {
                    HStack(spacing: 10) {
                        Text("fewer false starts").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                        Slider(value: $settings.wakeSensitivity, in: 0...1).tint(theme.colors.ink)
                        Text("hears more").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                    }
                }
                FormRow(label: "Wake model") {
                    HStack(spacing: 10) {
                        Text(WakeWordService.customModelInstalled ? "custom “Haku” model installed" : "on-device speech (train a custom model for lower power)")
                            .textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                        Button("show folder") {
                            try? FileManager.default.createDirectory(at: WakeWordService.modelDirectory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(WakeWordService.modelDirectory)
                        }
                        .buttonStyle(InkLinkStyle(size: 13))
                    }
                }
            }
            FormRow(label: "Confirm by voice") {
                HStack(spacing: 10) {
                    InkSwitch(isOn: $settings.confirmByVoice)
                    Text("“yes”, “no”, “send it”").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                }
            }
        }
    }

    private func hotkeyRow(_ label: String, _ name: KeyboardShortcuts.Name) -> some View {
        FormRow(label: label) {
            HStack(spacing: 6) {
                if recording == name {
                    KeyboardShortcuts.Recorder(for: name) { _ in recording = nil; tick += 1 }
                    Button("done") { recording = nil; tick += 1 }.buttonStyle(InkLinkStyle(size: 13))
                } else {
                    let parts = HotkeyManager.parts(name)
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in KeyCap(text: p) }
                    Spacer()
                    Button("change") { recording = name }.buttonStyle(InkLinkStyle(size: 13))
                }
            }
        }
    }

}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        @Bindable var themes = themes
        SectionHeading(title: "Theme")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(ThemeID.allCases) { id in ThemeTile(id: id, selected: themes.selectedThemeID == id) { themes.select(id) } }
        }
        FormStack {
            FormRow(label: "Mode") {
                InkSegmented(options: AppearanceMode.allCases, selection: $themes.mode) { $0.label }
                    .disabled(!themes.themeFamily.isMargin)
                    .opacity(themes.themeFamily.isMargin ? 1 : 0.5)
            }
            FormRow(label: "Highlighter") {
                HStack(spacing: 10) {
                    ForEach(HighlighterColor.allCases) { h in
                        Button { themes.highlighter = h } label: {
                            Circle().fill(h.color).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(theme.colors.paper, lineWidth: themes.highlighter == h ? 2 : 0).padding(-2))
                                .overlay(Circle().strokeBorder(theme.colors.ink, lineWidth: themes.highlighter == h ? 2 : 0).padding(-4))
                        }
                        .buttonStyle(.plain).accessibilityLabel(h.label)
                    }
                }
                .padding(.vertical, 4)
            }
            FormRow(label: "Widget shape") {
                InkSegmented(options: WidgetShape.allCases, selection: $themes.widgetShape) { $0.label }
            }
            FormRow(label: "Widget size") {
                InkSegmented(options: WidgetSize.allCases, selection: $themes.widgetSize) { $0.rawValue }.frame(maxWidth: 200)
            }
            FormRow(label: "Idle opacity") {
                HStack(spacing: 10) {
                    Slider(value: $themes.idleOpacity, in: 0.2...1).tint(theme.colors.ink)
                    Text("\(Int(themes.idleOpacity * 100))%").font(theme.font(.mono(12))).foregroundStyle(theme.colors.ink).frame(width: 34)
                }
            }
            FormRow(label: "Idle animation") {
                HStack(spacing: 10) {
                    InkSwitch(isOn: $themes.idleAnimation)
                    Text("\(themes.idleAnimation ? "On" : "Off") · always off with Reduce Motion").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
                }
            }
            FormRow(label: "Density") {
                InkSegmented(options: Density.allCases, selection: $themes.density) { $0.label }.frame(maxWidth: 260)
            }
        }
    }
}

/// `.th`: theme tile with a mini preview (ink bar + highlighter bar).
struct ThemeTile: View {
    @Environment(\.theme) private var theme
    let id: ThemeID
    let selected: Bool
    var action: () -> Void

    var body: some View {
        let t = Theme.resolve(id)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 1).fill(t.colors.ink).frame(height: 3).frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: 0.7, anchor: .leading)
                    RoundedRectangle(cornerRadius: 1).fill(t.highlight).frame(height: 6)
                        .scaleEffect(x: 0.44, anchor: .leading)
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 2).fill(t.colors.paper))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(t.colors.border.opacity(0.8), lineWidth: 1))
                .environment(\.colorScheme, t.scheme)
                Text(id.displayName).font(FontFactory.font(.newsreader, size: 13)).foregroundStyle(theme.colors.ink)
            }
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: Radii.button + 1).strokeBorder(theme.colors.ink, lineWidth: selected ? 2 : 0).padding(-3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About

struct AboutSettings: View {
    @Environment(\.theme) private var theme
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                CardGlyph(color: theme.colors.ink, highlight: theme.highlight, highlightTilt: -3, paperLine: theme.colors.paper)
                    .frame(width: 56, height: 56)
                (Text("Ha") + Text("ku").marked(theme)).font(FontFactory.font(.newsreader, size: 48, weight: .medium, italic: true))
                    .foregroundStyle(theme.colors.ink)
            }
            Text("Version \(version) · local voice assistant and task dispatcher").textRole(.ui, theme).foregroundStyle(theme.colors.muted)
            Text("Runs on your Mac: the model server, speech recognition and speech all stay local. Attachments are context only and are deleted after each task.")
                .font(theme.font(.listItem)).foregroundStyle(theme.colors.ink).fixedSize(horizontal: false, vertical: true)
            Text("Fonts: Newsreader, Atkinson Hyperlegible, IBM Plex Mono, Courier Prime — SIL Open Font License 1.1.")
                .textRole(.ui, theme).foregroundStyle(theme.colors.muted)
        }
        .padding(.top, 10)
    }
}
