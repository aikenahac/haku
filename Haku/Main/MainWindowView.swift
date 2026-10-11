import AppKit
import SwiftUI

/// What the main window shows. Chats use the conversation store's current id.
enum MainSection: Hashable {
    case chat, tasks, workflows, settings
}

@MainActor
@Observable
final class MainNavState {
    var section: MainSection = .chat
    var search = ""
    var renaming: UUID?
}

private struct EmbeddedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when Tasks/Workflows/Settings render inside the main window (no own close button).
    var embeddedInMainWindow: Bool {
        get { self[EmbeddedKey.self] }
        set { self[EmbeddedKey.self] = newValue }
    }
}

/// The full app window: chat history + Tasks + Workflows + Settings, in the Margin style.
struct MainWindowView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Bindable var nav: MainNavState
    var tasksSelection: TasksSelectionState
    var settingsSection: SettingsSectionState
    var showOnboarding: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(nav: nav)
                .frame(width: 256)
            VRule()
            Group {
                switch nav.section {
                case .chat: ChatDetailView(nav: nav)
                case .tasks: TasksView(selection: tasksSelection)
                case .workflows: WorkflowsView()
                case .settings:
                    SettingsView(state: settingsSection, showWorkflows: { nav.section = .workflows }, showOnboarding: showOnboarding)
                }
            }
            .environment(\.embeddedInMainWindow, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.colors.paper)
        .inkText(theme)
    }
}

// MARK: - Sidebar

struct MainSidebar: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Bindable var nav: MainNavState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CardGlyph(color: theme.colors.ink, highlight: theme.highlight, highlightTilt: -3, paperLine: theme.colors.paper)
                    .frame(width: 22, height: 22)
                (Text("Ha") + Text("ku").marked(theme))
                    .font(FontFactory.font(.newsreader, size: 24, weight: .medium, italic: true))
                    .foregroundStyle(theme.colors.ink)
                Spacer()
                Button { newChat() } label: { NewChatGlyph() }
                    .buttonStyle(IconButtonStyle()).help("New chat (⌘N)").accessibilityLabel("New chat")
            }
            .padding(.top, 40).padding(.horizontal, 16).padding(.bottom, 14)

            InkTextField(placeholder: "Search chats", text: $nav.search, mono: false)
                .padding(.horizontal, 14).padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = Self.group(model.conversations.search(nav.search))
                    if groups.isEmpty {
                        Text(nav.search.isEmpty ? "No chats yet. Hold \(HotkeyManager.display(.holdToTalk)) or say “Haku”." : "Nothing matches.")
                            .textRole(.label, theme).foregroundStyle(theme.colors.muted)
                            .padding(16)
                    }
                    ForEach(groups, id: \.0) { title, items in
                        SmallCaps(text: title, size: TypeScale.smallCapsTight)
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                        ForEach(items) { c in
                            ChatRow(conversation: c, selected: nav.section == .chat && model.conversations.currentID == c.id, nav: nav)
                                .onTapGesture {
                                    model.selectConversation(c.id)
                                    nav.section = .chat
                                }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            HRule()
            VStack(alignment: .leading, spacing: 2) {
                navItem("Tasks", .tasks, badge: model.tasks.running.count)
                navItem("Workflows", .workflows)
                navItem("Settings", .settings)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
        }
        .background(theme.colors.paper)
    }

    private func newChat() {
        model.newConversation()
        nav.section = .chat
        nav.search = ""
    }

    private func navItem(_ title: String, _ section: MainSection, badge: Int = 0) -> some View {
        Button { nav.section = section } label: {
            HStack {
                Text(title).font(theme.font(.listItem))
                    .foregroundStyle(nav.section == section ? theme.colors.ink : theme.colors.muted)
                Spacer()
                if badge > 0 {
                    Text("\(badge) running").textRole(.note, theme).foregroundStyle(theme.colors.blueInk)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Radii.button).fill(nav.section == section ? theme.colors.paper2 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Pinned · Today · Yesterday · Previous 7 days · Earlier.
    static func group(_ items: [Conversation]) -> [(String, [Conversation])] {
        let cal = Calendar.current
        var buckets: [(String, [Conversation])] = [("Pinned", []), ("Today", []), ("Yesterday", []), ("Previous 7 days", []), ("Earlier", [])]
        for c in items where !(c.entries.isEmpty && c.title == "New chat" && !c.pinned) || items.count == 1 {
            let i: Int
            if c.pinned { i = 0 }
            else if cal.isDateInToday(c.updated) { i = 1 }
            else if cal.isDateInYesterday(c.updated) { i = 2 }
            else if c.updated > Date.now.addingTimeInterval(-7 * 86400) { i = 3 }
            else { i = 4 }
            buckets[i].1.append(c)
        }
        return buckets.filter { !$0.1.isEmpty }
    }
}

struct NewChatGlyph: View {
    var body: some View {
        SVGShape("M12 5v14M5 12h14", viewBox: CGSize(width: 24, height: 24))
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}

struct ChatRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let conversation: Conversation
    let selected: Bool
    @Bindable var nav: MainNavState
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if nav.renaming == conversation.id {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain).font(theme.font(.listItem)).foregroundStyle(theme.colors.ink)
                    .onSubmit { commit() }
                    .onExitCommand { nav.renaming = nil }
                    .onAppear { draftTitle = conversation.title }
            } else {
                Text(conversation.title).font(theme.font(.listItem)).foregroundStyle(theme.colors.ink).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(conversation.preview.isEmpty ? "empty" : conversation.preview)
                    .font(FontFactory.font(theme.type.voice, size: 12.5, italic: theme.type.voice == .newsreader))
                    .foregroundStyle(theme.colors.muted).lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.time(conversation.updated)).font(theme.font(.mono(10))).foregroundStyle(theme.colors.muted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.colors.paper2 : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(theme.colors.marginLine).frame(width: Strokes.marginRule) }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(conversation.pinned ? "Unpin" : "Pin") { model.conversations.togglePin(conversation.id) }
            Button("Rename") { nav.renaming = conversation.id }
            Divider()
            Button("Delete", role: .destructive) { model.deleteConversation(conversation.id) }
        }
    }

    private func commit() {
        let t = draftTitle.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { model.conversations.rename(conversation.id, to: t) }
        nav.renaming = nil
    }

    static func time(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if d > Date.now.addingTimeInterval(-6 * 86400) { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Chat

/// A chat in the main window: same conversation + margin as the panel, wider, with history.
struct ChatDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Bindable var nav: MainNavState
    @State private var title = ""

    var body: some View {
        let model = self.model
        let convo = model.conversations.current
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("New chat", text: $title)
                        .textFieldStyle(.plain)
                        .font(theme.font(.windowTitle))
                        .foregroundStyle(theme.colors.ink)
                        .onSubmit { if let c = convo, !title.isEmpty { model.conversations.rename(c.id, to: title) } }
                    SmallCaps(text: subtitle(convo), size: TypeScale.smallCapsTight)
                }
                Spacer()
                if let c = convo, !c.entries.isEmpty {
                    Button("delete") { model.deleteConversation(c.id) }.buttonStyle(InkLinkStyle(size: 13, color: theme.colors.error))
                }
            }
            .padding(.top, 34).padding(.horizontal, 24).padding(.bottom, 14)
            HRule()
            ConversationView(messages: model.messages, notes: model.marginNotes,
                             actions: actions, liveTranscript: model.voice.isListening ? model.voice.partial : nil,
                             thinkingLabel: model.thinkingLabel)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            if !model.pendingAttachments.isEmpty {
                PendingAttachmentsRow(attachments: model.pendingAttachments, onRemove: { model.removeAttachment($0) })
            }
            if !model.workflows.workflows.isEmpty {
                HRule()
                WorkflowsRow(workflows: model.workflows.workflows.map(\.linkTitle), onRun: { model.runWorkflowFromUI(named: $0) })
            }
            HRule()
            InputBar(draft: Binding(get: { model.draft }, set: { model.draft = $0 }), actions: actions)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
                .background(theme.chrome.inputWell ? theme.colors.paper2 : .clear)
        }
        .onAppear { title = convo?.title ?? "" }
        .onChange(of: convo?.title) { _, t in title = t ?? "" }
        .onChange(of: convo?.id) { _, _ in title = model.conversations.current?.title ?? "" }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.attach(urls: [url]) } }
                }
            }
            return true
        }
    }

    private func subtitle(_ c: Conversation?) -> String {
        guard let c else { return "new chat" }
        let n = c.entries.count
        return "\(c.created.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(n) message\(n == 1 ? "" : "s") · \(model.modelDisplayName)"
    }

    private var actions: PanelActions {
        let model = self.model
        return PanelActions(
            openTasks: { nav.section = .tasks },
            openSettings: { nav.section = .settings },
            attach: {
                let p = NSOpenPanel()
                p.allowsMultipleSelection = true
                if p.runModal() == .OK { model.attach(urls: p.urls) }
            },
            send: { _ in model.submitDraft() },
            talkPressed: { down in down ? model.talkPressed() : model.talkReleased() },
            runWorkflow: { model.runWorkflowFromUI(named: $0) },
            showLog: { id in model.showTasks(id) },
            cancelJob: { model.cancelJob($0) },
            removeAttachment: { model.removeAttachment($0) },
            pasteImage: { model.attach(image: $0) },
            pasteFiles: { model.attach(urls: $0) })
    }
}
