import AppKit
import KeyboardShortcuts
import SwiftUI

/// Workflows editor (Margin-Workflows): list + editor for name, phrases, action, template, safety, hotkey.
struct WorkflowsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var selected: UUID?
    @State private var draft: Workflow?

    private var store: WorkflowStore { model.workflows }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Workflows").textRole(.windowTitle, theme).foregroundStyle(theme.colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("+ new workflow") { newWorkflow() }.buttonStyle(InkLinkStyle())
                Button { NSApp.keyWindow?.performClose(nil) } label: { CloseGlyph() }
                    .buttonStyle(IconButtonStyle()).keyboardShortcut("w", modifiers: .command)
            }
            .padding(.leading, 18).padding(.trailing, 10)
            .frame(height: 54)
            HRule()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.workflows) { w in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).font(theme.font(.listItem)).foregroundStyle(theme.colors.ink)
                                Text("“\(w.primaryPhrase)”").font(FontFactory.font(theme.type.voice, size: 12.5, italic: theme.type.voice == .newsreader))
                                    .foregroundStyle(theme.colors.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(selected == w.id ? theme.colors.paper2 : .clear)
                            .overlay(alignment: .bottom) { HRule() }
                            .contentShape(Rectangle())
                            .onTapGesture { select(w.id) }
                        }
                    }
                }
                .frame(width: 196)
                VRule()
                if draft != nil {
                    WorkflowEditor(workflow: Binding(get: { draft! }, set: { draft = $0 }),
                                   onSave: save, onDelete: delete, onTry: tryIt)
                        .id(draft!.id)
                } else {
                    Text("Pick a workflow or make a new one.").textRole(.label, theme).foregroundStyle(theme.colors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.colors.paper)
        .inkText(theme)
        .onAppear { if selected == nil, let f = store.workflows.first { select(f.id) } }
    }

    private func select(_ id: UUID) {
        selected = id
        draft = store.workflows.first { $0.id == id }
    }

    private func newWorkflow() {
        let w = Workflow(name: "New workflow", phrases: [], action: .askModel, folder: model.settings.defaultFolder, template: "{after}")
        store.upsert(w)
        select(w.id)
    }

    private func save() {
        guard var d = draft else { return }
        d.phrases = d.phrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if d.phrases.isEmpty { d.phrases = [d.name.lowercased()] }
        store.upsert(d)
        draft = d
    }

    private func delete() {
        guard let d = draft else { return }
        store.delete(d.id)
        KeyboardShortcuts.reset(.workflow(d.id))
        draft = nil
        selected = nil
        if let f = store.workflows.first { select(f.id) }
    }

    private func tryIt() {
        save()
        guard let d = draft else { return }
        model.showPanel()
        model.send(d.primaryPhrase, spoken: false)
    }
}

struct WorkflowEditor: View {
    @Environment(\.theme) private var theme
    @Binding var workflow: Workflow
    var onSave: () -> Void
    var onDelete: () -> Void
    var onTry: () -> Void
    @State private var newPhrase = ""
    @State private var addingPhrase = false
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        SmallCaps(text: "Workflow", size: TypeScale.smallCapsTight)
                        TextField("", text: $workflow.name)
                            .textFieldStyle(.plain)
                            .font(theme.font(.body(26)))
                            .foregroundStyle(theme.colors.ink)
                            .padding(.top, 2).padding(.bottom, 6)
                            .overlay(alignment: .bottom) { HRule() }
                    }
                    row("When I say") {
                        VStack(alignment: .leading, spacing: 8) {
                            FlowLayout(spacing: 6) {
                                ForEach(Array(workflow.phrases.enumerated()), id: \.offset) { i, p in
                                    HStack(spacing: 6) {
                                        Text(p).font(FontFactory.font(theme.type.voice, size: 14, italic: theme.type.voice == .newsreader))
                                            .foregroundStyle(theme.colors.ink)
                                        Button("×") { workflow.phrases.remove(at: i) }.buttonStyle(.plain)
                                            .font(theme.font(.ui)).foregroundStyle(theme.colors.muted).accessibilityLabel("Remove phrase")
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.paper2))
                                    .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
                                }
                                if addingPhrase {
                                    TextField("phrase", text: $newPhrase)
                                        .textFieldStyle(.plain).font(FontFactory.font(theme.type.voice, size: 14, italic: true))
                                        .frame(width: 160)
                                        .onSubmit { addPhrase() }
                                } else {
                                    Button("+ phrase") { addingPhrase = true }.buttonStyle(InkLinkStyle(size: 13))
                                }
                            }
                            InkCheckbox(title: "Also match similar wording", isOn: $workflow.matchSimilar, muted: true)
                        }
                    }
                    row("Do this") {
                        InkSegmented(options: Workflow.Action.allCases, selection: $workflow.action) { $0.label }
                    }
                    if workflow.action == .agent {
                        row("Agent") {
                            InkSegmented(options: AgentKind.allCases, selection: $workflow.agent) { $0.displayName }.frame(maxWidth: 240)
                        }
                    }
                    if workflow.action != .askModel {
                        row("Folder") {
                            HStack(spacing: 8) {
                                Text(workflow.folder.abbreviatingHome).font(theme.font(.mono(12.5))).foregroundStyle(theme.colors.ink)
                                Button("change") { chooseFolder() }.buttonStyle(InkLinkStyle(size: 13))
                            }
                        }
                    }
                    row(workflow.action == .shell ? "Command" : workflow.action == .script ? "Script" : workflow.action == .agent ? "Task" : "Prompt") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $workflow.template)
                                .font(workflow.action == .shell || workflow.action == .script ? theme.font(.mono(12.5)) : theme.font(.body(15)))
                                .foregroundStyle(theme.colors.ink)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .frame(minHeight: 96)
                                .background(theme.colors.paper2)
                                .overlay(Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1))
                            HStack(spacing: 6) {
                                Text("insert").font(FontFactory.font(theme.type.chrome, size: 13, italic: theme.type.chromeItalic)).foregroundStyle(theme.colors.muted)
                                ForEach(Workflow.variables, id: \.self) { v in
                                    VariableChip(name: v) { workflow.template += (workflow.template.hasSuffix(" ") || workflow.template.isEmpty ? "" : " ") + v }
                                }
                            }
                            (Text("{after}").font(theme.font(.mono(11.5))).foregroundColor(theme.colors.blueInk)
                             + Text(" is whatever you say after the phrase — “\(workflow.primaryPhrase) ")
                             + Text("and skip the tests").marked(theme) + Text("”."))
                                .font(FontFactory.font(theme.type.chrome, size: 12.5, italic: theme.type.chromeItalic))
                                .foregroundStyle(theme.colors.muted)
                        }
                    }
                    row("Safety") {
                        VStack(alignment: .leading, spacing: 8) {
                            InkCheckbox(title: "Confirm before running", isOn: Binding(
                                get: { workflow.confirmBeforeRunning && !workflow.alwaysAllow },
                                set: { workflow.confirmBeforeRunning = $0; if $0 { workflow.alwaysAllow = false } }))
                            if workflow.action == .agent {
                                InkCheckbox(title: "Allow file edits without asking", isOn: $workflow.allowEditsWithoutAsking)
                            }
                        }
                    }
                    row("Hotkey") {
                        HStack(spacing: 8) {
                            if recording || workflow.hasHotkey {
                                KeyboardShortcuts.Recorder(for: .workflow(workflow.id)) { s in
                                    workflow.hasHotkey = s != nil
                                    recording = false
                                }
                            } else {
                                Button("record a shortcut") { recording = true; workflow.hasHotkey = true }.buttonStyle(InkLinkStyle(size: 13))
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 20)
            }
            HStack(spacing: 8) {
                Button("delete", action: onDelete).buttonStyle(InkLinkStyle(color: theme.colors.error))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onTry) {
                    HStack(spacing: 8) { InkIcon(kind: .mic, lineWidth: 2).frame(width: 14, height: 14); Text("Try it") }
                }
                .buttonStyle(InkButtonStyle(height: 34))
                Button("Save", action: onSave).buttonStyle(InkButtonStyle(kind: .solid, height: 34))
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.top, 14).padding(.horizontal, 22).padding(.bottom, 16)
            .overlay(alignment: .top) { HRule().padding(.horizontal, 22) }
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).textRole(.label, theme).foregroundStyle(theme.colors.muted)
                .frame(width: 104, alignment: .leading).padding(.top, 6)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addPhrase() {
        let p = newPhrase.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { workflow.phrases.append(p) }
        newPhrase = ""
        addingPhrase = false
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.directoryURL = URL(fileURLWithPath: workflow.folder.expandingTilde)
        if p.runModal() == .OK, let u = p.url { workflow.folder = u.path.abbreviatingHome }
    }
}

/// Wrapping row layout for phrase chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
