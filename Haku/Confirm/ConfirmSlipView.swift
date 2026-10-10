import AppKit
import SwiftUI

/// The tear-off confirmation slip (Margin-Confirm): shell command, script, agent delegation, apply edits.
struct ConfirmSlipView: View {
    @Environment(\.theme) private var theme
    @Bindable var center: ConfirmationCenter
    let request: ConfirmationRequest
    var listening = false
    var onListConsequence: (String) -> Void = { _ in }
    var onChooseFolder: () -> Void = {}

    static let width: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                SmallCaps(text: request.source, size: TypeScale.smallCapsTight)
                Text(request.question).textRole(.windowTitle, theme).foregroundStyle(theme.colors.ink)
            }
            content
            if let label = request.alwaysAllowLabel {
                InkCheckbox(title: label, isOn: $center.alwaysAllow, muted: true)
            }
            HStack(spacing: Spacing.s8) {
                HStack(spacing: Spacing.s8) {
                    VoiceSquiggle(active: listening)
                    Text(request.voiceHint).font(FontFactory.font(theme.type.chrome, size: 13, italic: theme.type.chromeItalic))
                        .foregroundStyle(theme.colors.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { center.deny(source: "button") } label: { HStack(spacing: 8) { Text(request.denyLabel); KbdHint(key: "esc") } }
                    .buttonStyle(InkButtonStyle(kind: .outline, height: 36))
                    .keyboardShortcut(.cancelAction)
                Button { center.approve(source: "button") } label: { HStack(spacing: 8) { Text(request.approveLabel); KbdHint(key: "⏎") } }
                    .buttonStyle(InkButtonStyle(kind: .solid, height: 36))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Spacing.s14)
            .overlay(alignment: .top) { HRule() }
        }
        .padding(.top, 18).padding(.horizontal, 20).padding(.bottom, 16)
        .frame(width: Self.width)
        .background(PaperBackground(shape: UnevenRoundedRectangle(bottomLeadingRadius: theme.chrome.panelRadius,
                                                                  bottomTrailingRadius: theme.chrome.panelRadius)))
        .overlay(alignment: .top) { TearOffEdge() }
        .inkText(theme)
    }

    @ViewBuilder private var content: some View {
        switch request.kind {
        case let .shell(command, cwd):
            CodeBlock(text: command)
            consequences(cwd: cwd)
        case let .script(_, body, cwd):
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            CodeBlock(text: lines.prefix(12).joined(separator: "\n") + (lines.count > 12 ? "\n…" : ""))
            consequences(cwd: cwd, lineCount: lines.count)
        case .agent(let prompt, _, _, _):
            (Text("“") + Text(prompt) + Text("”"))
                .font(FontFactory.font(theme.type.voice, size: 16, italic: theme.type.voice == .newsreader))
                .foregroundStyle(theme.colors.ink)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            agentFields
        case let .applyEdits(_, _, proposal):
            ScrollView {
                Text(proposal).textRole(.listItem, theme).foregroundStyle(theme.colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
        }
    }

    private func consequences(cwd: String?, lineCount: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(request.consequences.filter(\.destructive).enumerated()), id: \.offset) { _, c in
                Text(c.text).wavy(theme)
                    .font(FontFactory.font(theme.type.voice, size: 15, italic: theme.type.voice == .newsreader))
                    .foregroundStyle(theme.colors.error)
            }
            HStack(spacing: 4) {
                if let cwd {
                    Text("in").textRole(.ui, theme)
                    Text(cwd.abbreviatingHome).font(theme.font(.mono(TypeScale.monoCode)))
                }
                ForEach(Array(request.consequences.filter { !$0.destructive }.enumerated()), id: \.offset) { _, c in
                    Text("· \(c.text)").textRole(.ui, theme)
                }
                if let list = request.consequences.first(where: { $0.listCommand != nil })?.listCommand {
                    Text("·").textRole(.ui, theme)
                    Button("list them") { onListConsequence(list) }.buttonStyle(InkLinkStyle(size: TypeScale.linkSmall))
                }
                if let lineCount, lineCount > 12 {
                    Text("· all \(lineCount) lines").textRole(.ui, theme)
                }
            }
            .foregroundStyle(theme.colors.muted)
        }
    }

    private var agentFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                fieldLabel("Agent")
                HStack(spacing: 6) {
                    Text(center.agent.displayName).textRole(.ui, theme).foregroundStyle(theme.colors.ink)
                    let other: AgentKind = center.agent == .claude ? .codex : .claude
                    Button("switch to \(other.displayName)") { center.agent = other }
                        .buttonStyle(InkLinkStyle(size: TypeScale.linkSmall))
                }
            }
            GridRow {
                fieldLabel("Folder")
                HStack(spacing: 6) {
                    Text(center.folder.abbreviatingHome).font(theme.font(.mono(TypeScale.monoCode))).foregroundStyle(theme.colors.ink)
                        .lineLimit(1).truncationMode(.head)
                    Button("change", action: onChooseFolder).buttonStyle(InkLinkStyle(size: TypeScale.linkSmall))
                }
            }
            GridRow {
                fieldLabel("Edits")
                InkSegmented(options: EditPermission.allCases, selection: $center.edits) { $0.label }
            }
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(FontFactory.font(theme.type.chrome, size: 13, italic: theme.type.chromeItalic))
            .foregroundStyle(theme.colors.muted)
            .frame(width: 84, alignment: .leading)
    }
}

/// `.code`: mono 12 / 1.65 on paper2 with a rule border.
struct CodeBlock: View {
    @Environment(\.theme) private var theme
    let text: String
    var body: some View {
        Text(text)
            .font(theme.font(.mono(TypeScale.monoCode)))
            .lineHeight(TypeScale.codeLineHeight, size: TypeScale.monoCode)
            .foregroundStyle(theme.colors.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(theme.colors.paper2)
            .overlay(Rectangle().strokeBorder(theme.colors.rule, lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Dashed 2 pt top edge of the slip.
struct TearOffEdge: View {
    @Environment(\.theme) private var theme
    var body: some View {
        RuleLine(axis: .horizontal, dashed: true)
            .stroke(theme.colors.rule, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(height: 2)
            .background(theme.colors.paper)
    }
}
