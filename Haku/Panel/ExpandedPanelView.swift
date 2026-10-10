import SwiftUI

/// Expanded panel (460×640): header, conversation + margin, workflows row, input.
struct ExpandedPanelView: View {
    @Environment(\.theme) private var theme
    var messages: [ChatMessage]
    var notes: [UUID: MarginNote]
    var workflows: [String]
    var modelName: String
    var date: Date = .now
    @Binding var draft: String
    var actions = PanelActions()
    var pending: [Attachment] = []
    /// What the recognizer has heard so far while listening.
    var liveTranscript: String?
    var thinkingLabel: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(modelName: modelName, date: date, actions: actions)
            HRule()
            ConversationView(messages: messages, notes: notes, actions: actions,
                             liveTranscript: liveTranscript, thinkingLabel: thinkingLabel)
            if !pending.isEmpty {
                PendingAttachmentsRow(attachments: pending, onRemove: actions.removeAttachment)
            }
            if !workflows.isEmpty {
                HRule()
                WorkflowsRow(workflows: workflows, onRun: actions.runWorkflow)
            }
            HRule()
            InputBar(draft: $draft, actions: actions)
        }
        .padding(.top, theme.chrome.bindingPanel)
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .paperSurface(binding: theme.chrome.bindingPanel, textured: true)
        .inkText(theme)
    }
}

/// Callbacks from the panel; all optional so previews can pass nothing.
struct PanelActions {
    var openTasks: () -> Void = {}
    var openSettings: () -> Void = {}
    var collapse: () -> Void = {}
    var attach: () -> Void = {}
    var send: (String) -> Void = { _ in }
    var talkPressed: (Bool) -> Void = { _ in }
    var runWorkflow: (String) -> Void = { _ in }
    var showLog: (UUID) -> Void = { _ in }
    var cancelJob: (UUID) -> Void = { _ in }
    var removeAttachment: (UUID) -> Void = { _ in }
    var pasteImage: (NSImage) -> Void = { _ in }
    var pasteFiles: ([URL]) -> Void = { _ in }
}

struct PanelHeader: View {
    @Environment(\.theme) private var theme
    let modelName: String
    let date: Date
    var actions: PanelActions

    var body: some View {
        HStack(spacing: Spacing.s10) {
            if theme.chrome.showsGlyph || theme.isMargin {
                CardGlyph(color: theme.colors.ink).frame(width: 18, height: 18)
            }
            Text(theme.copy.idleName)
                .textRole(.heading, theme)
                .fontWeight(theme.id == .typewriter || theme.id == .blueprint ? .bold : nil)
                .foregroundStyle(theme.colors.ink)
            SmallCaps(text: "\(Self.dateText(date, format: theme.copy.headerDate)) · \(modelName)",
                      textCase: theme.id == .typewriter ? nil : .uppercase)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: actions.openTasks) { InkIcon(kind: .tasks) }
                .buttonStyle(IconButtonStyle()).help("Tasks").accessibilityLabel("Tasks")
            Button(action: actions.openSettings) { InkIcon(kind: .settings) }
                .buttonStyle(IconButtonStyle()).help("Settings").accessibilityLabel("Settings")
            Button(action: actions.collapse) { InkIcon(kind: .collapse) }
                .buttonStyle(IconButtonStyle()).help("Collapse to widget").accessibilityLabel("Collapse to widget")
        }
        .padding(.leading, PanelMetrics.headerPadding.leading)
        .padding(.trailing, PanelMetrics.headerPadding.trailing)
        .frame(height: PanelMetrics.headerHeight)
    }

    static func dateText(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}

struct ConversationView: View {
    @Environment(\.theme) private var theme
    @Environment(\.staticRendering) private var staticRendering
    let messages: [ChatMessage]
    let notes: [UUID: MarginNote]
    var actions = PanelActions()
    var liveTranscript: String?
    var thinkingLabel: String?

    var body: some View {
        if staticRendering {
            rows.frame(maxHeight: .infinity, alignment: .top).clipped()
                .background(alignment: .trailing) { MarginRule().frame(width: PanelMetrics.marginWidth, alignment: .leading) }
        } else {
            ScrollViewReader { proxy in
                ScrollView { rows }
                    .onChange(of: messages.last?.plainText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: liveTranscript) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
                .scrollIndicators(.never)
                .defaultScrollAnchor(.bottom)
                .background(alignment: .trailing) {
                    MarginRule().frame(width: PanelMetrics.marginWidth, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
        }
    }

    private var rows: some View {
        let d = theme.density
        return VStack(alignment: .leading, spacing: d.messageGap) {
                ForEach(messages) { msg in
                    HStack(alignment: .top, spacing: 0) {
                        MessageView(message: msg)
                            .padding(.leading, d.bodyPaddingH + 1)
                            .padding(.trailing, d.bodyPaddingH - 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if let id = msg.jobID, let note = notes[id] {
                                MarginNoteView(note: note, onLog: { actions.showLog(id) }, onCancel: { actions.cancelJob(id) })
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                        .padding(.horizontal, PanelMetrics.marginPadding.h)
                        .frame(width: PanelMetrics.marginWidth, alignment: .leading)
                    }
                    .id(msg.id)
                }
                if let live = liveTranscript, !live.isEmpty {
                    MessageView(message: ChatMessage(.user, live + "…"))
                        .opacity(0.7)
                        .padding(.leading, d.bodyPaddingH + 1)
                        .padding(.trailing, PanelMetrics.marginWidth + d.bodyPaddingH)
                }
                if let label = thinkingLabel {
                    Text(label).textRole(.note, theme).foregroundStyle(theme.colors.muted)
                        .padding(.leading, d.bodyPaddingH + 1)
                }
                if messages.isEmpty && liveTranscript == nil {
                    Text("Hold \(HotkeyManager.display(.holdToTalk)) and say what you need, or write below.")
                        .textRole(.label, theme).foregroundStyle(theme.colors.muted)
                        .padding(.leading, d.bodyPaddingH + 1)
                        .padding(.trailing, PanelMetrics.marginWidth + d.bodyPaddingH)
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.vertical, d.bodyPaddingV)
    }
}

/// The vertical margin rule: single (Margin), double red (Legal pad) or dashed (Typewriter).
struct MarginRule: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            switch theme.marginRule {
            case .single:
                Rectangle().fill(theme.colors.marginLine).frame(width: Strokes.marginRule)
            case .double:
                Rectangle().fill(theme.colors.marginLine).frame(width: 1)
                Spacer().frame(width: 2)
                Rectangle().fill(theme.colors.marginLine).frame(width: 1)
            case .dashed:
                VRule(color: theme.colors.marginLine)
            }
            Spacer(minLength: 0)
        }
        .offset(x: theme.marginRule == .double ? -3 : 0)
        .accessibilityHidden(true)
    }
}

struct MessageView: View {
    @Environment(\.theme) private var theme
    let message: ChatMessage

    var body: some View {
        let d = theme.density
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ForEach(message.attachments) { TapedPhoto(attachment: $0) }
            text
                .lineHeight(d.lineHeight, size: d.bodySize)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var text: Text {
        let d = theme.density
        if message.role == .user {
            let t = theme.type
            let font = t.userLine == t.voice
                ? FontFactory.font(t.userLine, size: d.bodySize, italic: t.userLineItalic)
                : FontFactory.font(t.userLine, size: d.bodySize - 5)
            return Text("\(theme.copy.userPrefix) \(message.plainText)")
                .font(font)
                .foregroundColor(theme.colors.muted)
        }
        return message.spans.reduce(Text("")) { acc, span in
            switch span {
            case .text(let s):
                acc + Text(s).font(theme.font(.body(d.bodySize))).foregroundColor(theme.colors.ink)
            case .mark(let s):
                acc + Text(s).marked(theme).font(theme.font(.body(d.bodySize))).foregroundColor(theme.colors.ink)
            case .path(let s):
                acc + Text(s).font(theme.font(.mono(TypeScale.inlinePath))).foregroundColor(theme.colors.ink)
            }
        }
    }
}

/// Blue-ink italic note in the margin with `log` / `cancel` links.
struct MarginNoteView: View {
    @Environment(\.theme) private var theme
    let note: MarginNote
    var onLog: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        let color = note.running ? theme.colors.blueInk : theme.colors.muted
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(note.agent).fontWeight(.medium)
            Text(note.status)
            if let detail = note.detail { Text(detail) }
            HStack(spacing: Spacing.s10) {
                Button("log", action: onLog).buttonStyle(InkLinkStyle(size: TypeScale.linkSmall))
                if note.running {
                    Button("cancel", action: onCancel).buttonStyle(InkLinkStyle(size: TypeScale.linkSmall))
                }
            }
            .padding(.top, Spacing.xs)
        }
        .textRole(.note, theme)
        .lineHeight(TypeScale.noteLineHeight, size: TypeScale.note)
        .foregroundStyle(color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Attachment as a taped photo: paper2 frame, −1.5° tilt, translucent highlighter tape.
struct TapedPhoto: View {
    @Environment(\.theme) private var theme
    let attachment: Attachment
    var image: Image?
    var onRemove: (() -> Void)?

    private var loaded: Image? {
        if let image { return image }
        guard attachment.isImage, let url = attachment.url, let ns = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: ns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let image = loaded {
                    image.resizable().scaledToFill()
                } else {
                    // Placeholder lines (as in the mockup) until a thumbnail loads.
                    Canvas { ctx, size in
                        var y: CGFloat = 0
                        while y < size.height {
                            ctx.fill(Path(CGRect(x: 0, y: size.height - y - 1, width: size.width, height: 1)), with: .color(theme.colors.rule))
                            y += 9
                        }
                    }
                }
            }
            .frame(width: PanelMetrics.photoThumb.width, height: PanelMetrics.photoThumb.height)
            .clipped()
            Text(attachment.fileName)
                .font(theme.font(.mono(TypeScale.monoCaption)))
                .foregroundStyle(theme.colors.muted)
                .lineLimit(1)
        }
        .padding(PanelMetrics.photoPadding)
        .background(theme.colors.paper2)
        .overlay(Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.highlight.opacity(PanelMetrics.tapeOpacity))
                .frame(width: PanelMetrics.tape.width, height: PanelMetrics.tape.height)
                .offset(y: PanelMetrics.tapeOffset)
        }
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                Button(action: onRemove) { Text("×").font(theme.font(.ui)).foregroundStyle(theme.colors.muted) }
                    .buttonStyle(.plain).padding(4).help("Remove attachment")
            }
        }
        .rotationEffect(.degrees(PanelMetrics.photoRotation))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attachment \(attachment.fileName)")
    }
}

/// Attachments waiting to be sent with the next message.
struct PendingAttachmentsRow: View {
    @Environment(\.theme) private var theme
    let attachments: [Attachment]
    var onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s14) {
                ForEach(attachments) { a in
                    TapedPhoto(attachment: a, onRemove: { onRemove(a.id) })
                }
            }
            .padding(.horizontal, PanelMetrics.inputPadding.leading)
            .padding(.top, Spacing.s14).padding(.bottom, Spacing.s8)
        }
        .scrollIndicators(.never)
    }
}

struct WorkflowsRow: View {
    @Environment(\.theme) private var theme
    let workflows: [String]
    var onRun: (String) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s10) {
            Text("Workflows:").textRole(.label, theme).foregroundStyle(theme.colors.muted)
            ForEach(workflows, id: \.self) { name in
                Button(name) { onRun(name) }.buttonStyle(InkLinkStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelMetrics.workflowsPadding.h)
        .padding(.vertical, PanelMetrics.workflowsPadding.v)
    }
}

struct InputBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.staticRendering) private var staticRendering
    @Binding var draft: String
    var actions = PanelActions()
    @State private var talking = false

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button(action: actions.attach) { InkIcon(kind: .attach) }
                .buttonStyle(IconButtonStyle()).help("Attach file or image").accessibilityLabel("Attach file or image")
            field
                .padding(.horizontal, 2)
                .frame(height: PanelMetrics.inputHeight)
                .overlay(alignment: .bottom) {
                    if theme.ruleStyle == .dashed { HRule(color: theme.colors.ink) }
                    else { Rectangle().fill(theme.colors.ink).frame(height: Strokes.inputUnderline) }
                }
                .onSubmit { actions.send(draft) }
                .onPasteCommand(of: [.fileURL, .png, .tiff, .image]) { providers in
                    for p in providers {
                        if p.canLoadObject(ofClass: URL.self) {
                            _ = p.loadObject(ofClass: URL.self) { url, _ in
                                if let url { Task { @MainActor in actions.pasteFiles([url]) } }
                            }
                        } else if p.canLoadObject(ofClass: NSImage.self) {
                            _ = p.loadObject(ofClass: NSImage.self) { img, _ in
                                if let img = img as? NSImage { Task { @MainActor in actions.pasteImage(img) } }
                            }
                        }
                    }
                }
                .accessibilityLabel("Message Haku")
            micButton
        }
        .padding(.top, PanelMetrics.inputPadding.top)
        .padding(.leading, PanelMetrics.inputPadding.leading)
        .padding(.bottom, PanelMetrics.inputPadding.bottom)
        .padding(.trailing, PanelMetrics.inputPadding.trailing)
        .background(theme.chrome.inputWell ? theme.colors.paper2 : .clear)
    }

    @ViewBuilder private var field: some View {
        if staticRendering {
            Text(draft.isEmpty ? theme.copy.placeholder : draft)
                .font(placeholderFont)
                .foregroundStyle(draft.isEmpty ? theme.colors.muted : theme.colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("", text: $draft, prompt: Text(theme.copy.placeholder)
                .font(placeholderFont).foregroundColor(theme.colors.muted))
                .textFieldStyle(.plain)
                .font(placeholderFont)
                .foregroundStyle(theme.colors.ink)
        }
    }

    private var placeholderFont: Font {
        switch theme.type.chrome {
        case .newsreader: FontFactory.font(.newsreader, size: PanelMetrics.inputFont, italic: true)
        case .plexMono: FontFactory.font(.plexMono, size: TypeScale.monoCode)
        default: FontFactory.font(theme.type.chrome, size: TypeScale.label)
        }
    }

    @ViewBuilder private var micButton: some View {
        let label = Group {
            switch theme.chrome.micButton {
            case .round:
                InkIcon(kind: .mic, lineWidth: 2).frame(width: 16, height: 16)
                    .foregroundStyle(theme.colors.paper)
                    .frame(width: PanelMetrics.micButton, height: PanelMetrics.micButton)
                    .background(Circle().fill(theme.colors.ink))
            case .square:
                InkIcon(kind: .mic, lineWidth: 2).frame(width: 14, height: 14)
                    .foregroundStyle(theme.colors.ink)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().strokeBorder(theme.colors.ink, lineWidth: 1))
            case .bracketText:
                Text("[mic]").font(theme.font(.mono(12))).foregroundStyle(theme.colors.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(Rectangle().strokeBorder(theme.colors.ink, lineWidth: 1))
            }
        }
        label
            .scaleEffect(talking ? 0.94 : 1)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !talking { talking = true; actions.talkPressed(true) } }
                .onEnded { _ in talking = false; actions.talkPressed(false) })
            .accessibilityLabel("Hold to talk")
            .accessibilityAddTraits(.isButton)
    }
}
