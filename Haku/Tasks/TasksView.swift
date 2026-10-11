import AppKit
import SwiftUI

/// Tasks window (Margin-Tasks): filter tabs, 236 pt job list, detail with steps, live log, summary, actions.
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @Bindable var selection: TasksSelectionState
    @State private var filter: Filter = .running

    enum Filter: String, CaseIterable, Identifiable {
        case running = "Running", done = "Done", failed = "Failed", all = "All"
        var id: String { rawValue }
    }

    private var jobs: [AgentJob] { model.tasks.jobs }

    private func filtered(_ f: Filter) -> [AgentJob] {
        switch f {
        case .running: jobs.filter { $0.isActive || $0.status == .awaitingApproval }
        case .done: jobs.filter { $0.status == .done }
        case .failed: jobs.filter { $0.status == .failed || $0.status == .cancelled }
        case .all: jobs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(title: "Tasks") {
                HStack(spacing: 16) {
                    ForEach(Filter.allCases) { f in
                        let n = filtered(f).count
                        TabLink(title: f == .all ? f.rawValue : "\(f.rawValue) \(n)", on: filter == f) { filter = f }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HRule()
            HStack(spacing: 0) {
                list.frame(width: 236)
                VRule()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(theme.colors.paper)
        .background(TextureView(style: theme.texture))
        .inkText(theme)
        .onAppear {
            if selection.selected == nil { selection.selected = filtered(filter).first?.id ?? jobs.first?.id }
            if let id = selection.selected, let j = model.tasks.job(id), !filtered(filter).contains(j) { filter = .all }
        }
        .onChange(of: selection.selected) { _, id in
            if let id, let j = model.tasks.job(id), !filtered(filter).contains(j) { filter = .all }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let items = filtered(filter)
                if items.isEmpty {
                    Text(filter == .running ? "Nothing running." : "Nothing here yet.")
                        .textRole(.label, theme).foregroundStyle(theme.colors.muted)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(items) { job in
                    TaskRow(job: job, selected: selection.selected == job.id)
                        .onTapGesture { selection.selected = job.id }
                }
            }
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var detail: some View {
        if let id = selection.selected, let job = model.tasks.job(id) {
            TaskDetail(job: job)
        } else {
            VStack(spacing: 10) {
                Text("No task selected").textRole(.windowTitle, theme).foregroundStyle(theme.colors.muted)
                Text("Ask Haku to hand something to Claude Code or Codex.").textRole(.label, theme).foregroundStyle(theme.colors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Header row shared by the app windows: serif title + trailing content + close.
struct WindowHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.embeddedInMainWindow) private var embedded
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 18) {
            Text(title).textRole(.windowTitle, theme).foregroundStyle(theme.colors.ink)
            trailing
            if !embedded {
                Button { NSApp.keyWindow?.performClose(nil) } label: { CloseGlyph() }
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut("w", modifiers: .command)
                    .help("Close").accessibilityLabel("Close \(title.lowercased())")
            }
        }
        .padding(.leading, embedded ? 24 : 18).padding(.trailing, 10)
        .padding(.top, embedded ? 26 : 0)
        .frame(height: embedded ? 80 : 54)
    }
}

struct CloseGlyph: View {
    var body: some View {
        SVGShape("M7 7l10 10M17 7L7 17", viewBox: CGSize(width: 24, height: 24))
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}

/// `.tab`: serif 14 muted; active = ink with 1.5 pt underline offset 6.
struct TabLink: View {
    @Environment(\.theme) private var theme
    let title: String
    let on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FontFactory.font(theme.type.voice == .newsreader ? .newsreader : theme.type.chrome, size: 14))
                .foregroundStyle(on ? theme.colors.ink : theme.colors.muted)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    if on { Rectangle().fill(theme.colors.ink).frame(height: 1.5).offset(y: 3) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TaskRow: View {
    @Environment(\.theme) private var theme
    let job: AgentJob
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SmallCaps(text: job.runner.displayName, size: 10)
            Text(job.title).font(theme.font(.body(15))).lineHeight(1.3, size: 15)
                .foregroundStyle(theme.colors.ink).lineLimit(2)
            Text(job.directory ?? "no working dir").font(theme.font(.mono(TypeScale.monoPath)))
                .foregroundStyle(theme.colors.muted).lineLimit(1).truncationMode(.middle)
            TaskStatusText(job: job)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12).padding(.bottom, 12).padding(.leading, 16).padding(.trailing, 14)
        .background(selected ? theme.colors.paper2 : .clear)
        .overlay(alignment: .bottom) { HRule() }
        .contentShape(Rectangle())
    }
}

/// `.st`: italic 13 — blue running, muted done, red wavy failed.
struct TaskStatusText: View {
    @Environment(\.theme) private var theme
    let job: AgentJob

    var body: some View {
        let base = Text(job.statusLine)
        Group {
            switch job.status {
            case .failed: base.wavy(theme).foregroundColor(theme.colors.error)
            case .running, .queued, .awaitingApproval: base.foregroundColor(theme.colors.blueInk)
            default: base.foregroundColor(theme.colors.muted)
            }
        }
        .textRole(.note, theme)
    }
}

struct TaskDetail: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let job: AgentJob
    @State private var follow = true
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SmallCaps(text: "\(job.runner.displayName) · \(headerStatus)",
                              color: job.isActive ? theme.colors.blueInk : job.status == .failed ? theme.colors.error : nil)
                    Text(job.title).font(theme.font(.body(TypeScale.pageTitle))).lineHeight(1.15, size: TypeScale.pageTitle)
                        .foregroundStyle(theme.colors.ink).textSelection(.enabled)
                }
                meta
                if !job.steps.isEmpty { steps }
                if job.isActive || job.summary == nil { logSection }
                if let summary = job.summary, !job.isActive {
                    VStack(alignment: .leading, spacing: 8) {
                        label("Summary")
                        MessageSpan.parse(summary).reduce(Text("")) { acc, span in
                            switch span {
                            case .text(let s): acc + Text(s)
                            case .mark(let s): acc + Text(s).marked(theme)
                            case .path(let s): acc + Text(s).font(theme.font(.mono(13)))
                            }
                        }
                        .font(theme.font(.body(16))).lineHeight(1.5, size: 16)
                        .foregroundStyle(theme.colors.ink).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let err = job.errorMessage, job.status == .failed, err != job.summary {
                    Text(err).wavy(theme).textRole(.note, theme).foregroundStyle(theme.colors.error)
                }
                if !job.changedFiles.isEmpty && !job.isActive {
                    VStack(alignment: .leading, spacing: 6) {
                        label("Changed")
                        LogBox(lines: job.changedFiles.map { AgentJob.LogLine(date: .now, text: $0, kind: .output) }, timestamps: false, lineHeight: 1.8)
                    }
                }
                if !job.isActive && job.summary != nil { logDisclosure }
                actions
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerStatus: String {
        switch job.status {
        case .running: return "running"
        case .queued: return "queued"
        case .done: return "done in \(job.durationText)"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .awaitingApproval: return "waiting for your ok"
        }
    }

    private var meta: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                label13("Working dir")
                Text(job.directory ?? "no working dir").font(theme.font(.mono(12))).foregroundStyle(theme.colors.ink)
            }
            GridRow {
                if job.isActive {
                    label13("Started")
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(job.started.formatted(date: .omitted, time: .shortened)) · \(job.durationText) ago")
                            .textRole(.ui, theme).foregroundStyle(theme.colors.ink)
                    }
                } else {
                    label13("Ran")
                    Text("\(job.started.formatted(date: .omitted, time: .shortened)) – \((job.ended ?? .now).formatted(date: .omitted, time: .shortened))")
                        .textRole(.ui, theme).foregroundStyle(theme.colors.ink)
                }
            }
            if !job.spokenAsk.isEmpty {
                GridRow {
                    label13("Asked")
                    Text("“\(job.spokenAsk)”").font(FontFactory.font(theme.type.voice, size: 13, italic: theme.type.voice == .newsreader))
                        .foregroundStyle(theme.colors.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            GridRow {
                label13("Permissions")
                Text(job.permission.sentence + (job.approvals > 0 ? " · \(job.approvals) approval\(job.approvals == 1 ? "" : "s")" : ""))
                    .textRole(.ui, theme).foregroundStyle(theme.colors.ink)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(job.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(theme.font(.mono(11)))
                        .foregroundStyle(step.state == .now ? theme.colors.blueInk : theme.colors.muted)
                        .frame(width: 18, alignment: .leading)
                    Group {
                        switch step.state {
                        case .done: Text(step.text).strikethrough(true, color: theme.colors.rule).foregroundColor(theme.colors.muted)
                        case .now: Text(step.text).marked(theme).foregroundColor(theme.colors.ink)
                        case .todo: Text(step.text).foregroundColor(theme.colors.ink)
                        }
                    }
                    .font(theme.font(.listItem))
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                label("Live log")
                Spacer()
                Button(follow ? "following" : "follow") { follow.toggle() }.buttonStyle(InkLinkStyle(size: 13))
            }
            LogBox(lines: Array(job.log.suffix(400)), follow: follow, maxHeight: 280)
        }
    }

    @State private var showFullLog = false
    private var logDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(showFullLog ? "hide log" : "show log (\(job.log.count) lines)") { showFullLog.toggle() }
                .buttonStyle(InkLinkStyle(size: 13))
            if showFullLog { LogBox(lines: Array(job.log.suffix(400)), follow: false, maxHeight: 280) }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if job.isActive {
                Button("Cancel") { model.cancelJob(job.id) }.buttonStyle(InkButtonStyle(kind: .warn))
                Button("Open in Terminal") { Terminal.open(dir: job.directory ?? "~") }.buttonStyle(InkButtonStyle())
            } else if job.status == .awaitingApproval {
                Button("Apply changes") { model.approveEdits(job.id) }.buttonStyle(InkButtonStyle(kind: .solid))
                Button("Copy summary") { copy() }.buttonStyle(InkButtonStyle())
            } else {
                if !job.changedFiles.isEmpty {
                    Button("Open diff") { Terminal.open(dir: job.directory ?? "~", command: "git --no-pager diff --stat; git diff") }
                        .buttonStyle(InkButtonStyle(kind: .solid))
                }
                Button(copied ? "Copied" : "Copy summary") { copy() }.buttonStyle(InkButtonStyle()).disabled(job.summary == nil)
                Button(job.status == .failed ? "Retry" : "Run again") { model.retryJob(job.id) }.buttonStyle(InkButtonStyle())
                Button("Open in Terminal") { Terminal.open(dir: job.directory ?? "~") }.buttonStyle(InkButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(job.summary ?? "", forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    private func label(_ s: String) -> some View {
        Text(s).textRole(.label, theme).foregroundStyle(theme.colors.muted)
    }

    private func label13(_ s: String) -> some View {
        Text(s).font(FontFactory.font(theme.type.chrome, size: 13, italic: theme.type.chromeItalic))
            .foregroundStyle(theme.colors.muted).frame(width: 96, alignment: .leading)
    }
}

/// `.log`: mono 11.5 / 1.7 on paper2; timestamps muted, failures red.
struct LogBox: View {
    @Environment(\.theme) private var theme
    let lines: [AgentJob.LogLine]
    var timestamps = true
    var follow = false
    var lineHeight: CGFloat = TypeScale.logLineHeight
    var maxHeight: CGFloat? = nil

    private static let ts: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                        (timestamps ? Text(Self.ts.string(from: l.date) + " ").foregroundColor(theme.colors.muted) : Text(""))
                            + Text(l.text).foregroundColor(color(l.kind))
                    }
                    .font(theme.font(.mono(TypeScale.monoLog)))
                    .lineHeight(lineHeight, size: TypeScale.monoLog)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: maxHeight == nil)
            .background(theme.colors.paper2)
            .overlay(Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1))
            .onChange(of: lines.count) { _, _ in if follow { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { if follow { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private func color(_ k: AgentJob.LogLine.Kind) -> Color {
        switch k {
        case .fail: theme.colors.error
        case .info: theme.colors.muted
        default: theme.colors.ink
        }
    }
}
