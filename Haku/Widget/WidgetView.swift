import SwiftUI

/// The floating widget, drawn for any state, shape, size and theme.
/// Pure view: the window, gestures and opacity live in `WidgetController`.
struct WidgetView: View {
    @Environment(\.theme) private var theme
    let state: WidgetState
    var shape: WidgetShape = .slip
    var size: WidgetSize = .medium
    var hotkeyHint: String?
    var onStop: () -> Void = {}
    var onFix: () -> Void = {}

    private var m: WidgetMetrics { .of(size) }

    var body: some View {
        Group {
            switch shape {
            case .slip: slip
            case .indexTab: indexTab
            case .seal: SealWidget(state: state, onStop: onStop, onFix: onFix)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.accessibilityDescription)
    }

    // MARK: Slip

    private var slipShape: AnyInsettableShape {
        if theme.chrome.shippingTag {
            let r = min(WidgetMetrics.tagEndRadius, m.height / 2)
            return AnyInsettableShape(UnevenRoundedRectangle(
                topLeadingRadius: theme.chrome.widgetRadius, bottomLeadingRadius: theme.chrome.widgetRadius,
                bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous))
        }
        return AnyInsettableShape(RoundedRectangle(cornerRadius: theme.chrome.widgetRadius, style: .continuous))
    }

    private var slip: some View {
        WidgetContent(state: state, metrics: m, hotkeyHint: hotkeyHint, onStop: onStop, onFix: onFix)
            .padding(.leading, theme.chrome.shippingTag ? WidgetMetrics.tagLeading : m.paddingLeading)
            .padding(.trailing, m.paddingTrailing)
            .padding(.top, theme.chrome.bindingWidget)
            .frame(width: m.width, height: m.height + theme.chrome.bindingWidget)
            .background(PaperBackground(shape: slipShape, binding: theme.chrome.bindingWidget))
            .overlay(alignment: .leading) {
                if theme.chrome.shippingTag { tagHole }
            }
            .overlay(alignment: .topTrailing) { stampOverlay }
    }

    private var tagHole: some View {
        Circle()
            .fill(theme.colors.desk)
            .overlay(Circle().strokeBorder(theme.colors.tagHole ?? theme.colors.ink, lineWidth: 1.5))
            .frame(width: WidgetMetrics.tagHole + 1.5, height: WidgetMetrics.tagHole + 1.5)
            .padding(.leading, WidgetMetrics.tagHoleInset)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var stampOverlay: some View {
        if case let .agentRunning(_, _, _, jobs) = state, theme.chrome.stampOverlay {
            StampBadge(count: jobs)
                .offset(x: WidgetMetrics.stampOffset, y: -WidgetMetrics.stampOffset)
        }
    }

    // MARK: Index tab

    private var indexTab: some View {
        let tab = WidgetMetrics.tabSize
        let r = theme.chrome.widgetRadius
        let bodyShape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: r,
                                               bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        let tabShape = UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0,
                                              bottomTrailingRadius: 0, topTrailingRadius: theme.chrome.squareCorners ? 0 : 8,
                                              style: .continuous)
        return VStack(alignment: .leading, spacing: -WidgetMetrics.tabOverlap) {
            ZStack {
                tabShape.fill(theme.colors.paper)
                tabShape.stroke(theme.colors.border, lineWidth: theme.chrome.borderWidth)
                // Hide the stroke where the tab joins the body.
                Rectangle().fill(theme.colors.paper).frame(height: WidgetMetrics.tabOverlap + 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, theme.chrome.borderWidth)
            }
            .frame(width: tab.width, height: tab.height)
            .zIndex(1)
            WidgetContent(state: state, metrics: m, hotkeyHint: hotkeyHint, showGlyph: false, onStop: onStop, onFix: onFix)
                .padding(.leading, m.paddingLeading)
                .padding(.trailing, m.paddingTrailing)
                .frame(width: m.width, height: m.height)
                .background(PaperBackground(shape: bodyShape))
                .overlay(alignment: .topTrailing) { stampOverlay }
        }
    }
}

/// The glyph · state text · trailing element row shared by Slip and Index tab.
struct WidgetContent: View {
    @Environment(\.theme) private var theme
    let state: WidgetState
    let metrics: WidgetMetrics
    var hotkeyHint: String?
    var showGlyph = true
    var onStop: () -> Void = {}
    var onFix: () -> Void = {}

    private var m: WidgetMetrics { metrics }
    private var stateRole: TextRole { .widgetState(m.stateFont) }

    var body: some View {
        HStack(spacing: m.gap) {
            if showGlyph && theme.chrome.showsGlyph { glyph }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .inkText(theme)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .error:
            CardGlyph(style: .outlined, color: theme.colors.error).frame(width: m.glyph, height: m.glyph)
        case .listening:
            CardGlyph(color: theme.colors.ink, highlight: theme.highlight).frame(width: m.glyph, height: m.glyph)
        default:
            CardGlyph(color: theme.colors.ink).frame(width: m.glyph, height: m.glyph)
        }
    }

    private func stateText(_ s: String) -> some View {
        Text(s).textRole(stateRole, theme).foregroundStyle(theme.colors.ink).lineLimit(1)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle:
            stateText(theme.copy.idleName).frame(maxWidth: .infinity, alignment: .leading)
            SmallCaps(text: hotkeyHint ?? theme.copy.hotkeyHint, size: m.smallCaps,
                      textCase: theme.id == .typewriter ? .lowercase : .uppercase)

        case let .listening(level, elapsed):
            switch theme.listening {
            case .cursor:
                HStack(spacing: 0) {
                    Text(theme.copy.listening + "_").marked(theme)
                        .textRole(stateRole, theme).lineLimit(1)
                    BlockCursor(height: m.stateFont * theme.type.stateScale + 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.timer(elapsed))
                    .font(theme.font(.mono(m.smallCaps + 1)))
                    .foregroundStyle(theme.colors.muted)
            case .zigzag:
                Text(theme.copy.listening).marked(theme)
                    .textRole(stateRole, theme).foregroundStyle(theme.colors.ink).lineLimit(1)
                    .padding(.horizontal, 2)
                ListeningZigzag(level: level, size: m.squiggle)
                    .frame(maxWidth: .infinity)
            case let .squiggle(stroke, useBlueInk):
                Text(theme.copy.listening).marked(theme)
                    .textRole(stateRole, theme).foregroundStyle(theme.colors.ink).lineLimit(1)
                ListeningSquiggle(level: level, size: m.squiggle, stroke: stroke,
                                  color: useBlueInk ? theme.colors.blueInk : nil)
                    .frame(maxWidth: .infinity)
            }

        case .thinking:
            stateText(theme.copy.thinking).frame(maxWidth: .infinity, alignment: .leading)
            InkDots(dot: m.dot)

        case .speaking:
            stateText(theme.copy.speaking)
                .overlay(alignment: .bottomLeading) {
                    HandUnderline(size: m.underline).offset(y: m.underline.height + 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("stop", action: onStop).buttonStyle(InkLinkStyle(size: m.linkFont))

        case let .agentRunning(agent, done, total, jobs):
            stateText(agent).frame(maxWidth: .infinity, alignment: .leading)
            agentProgress(done: done, total: total, jobs: jobs)

        case let .error(reason):
            Text(reason).wavy(theme)
                .textRole(stateRole, theme).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("fix", action: onFix).buttonStyle(InkLinkStyle(size: m.linkFont))
        }
    }

    @ViewBuilder private func agentProgress(done: Int, total: Int, jobs: Int) -> some View {
        let count = SmallCaps(text: "\(done)/\(total)", size: m.smallCaps)
        switch theme.progress {
        case .tally:
            ProgressMarks(done: done, total: total, size: m.tally)
            if theme.id != .legalPad { count }
        case .squareCells:
            count.foregroundStyle(theme.colors.ink)
            ProgressMarks(done: done, total: total, size: m.tally)
        case .bracketHashes:
            ProgressMarks(done: done, total: total, fontSize: m.stateFont * theme.type.stateScale)
        case .stamp:
            ProgressMarks(done: done, total: total, stampCount: jobs)
        }
    }

    static func timer(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Seal: 52 pt round stamp with an italic "h". Non-idle states are derived (see DESIGN_NOTES).
struct SealWidget: View {
    @Environment(\.theme) private var theme
    let state: WidgetState
    var onStop: () -> Void = {}
    var onFix: () -> Void = {}

    var body: some View {
        let ringColor: Color = {
            if case .error = state { return theme.colors.error }
            return theme.colors.ink
        }()
        ZStack {
            PaperBackground(shape: Circle(), shadow: theme.chrome.shadow == .none ? ShadowStyle.none : .seal)
            Circle()
                .strokeBorder(ringColor, lineWidth: Strokes.stamp)
                .frame(width: WidgetMetrics.sealRing, height: WidgetMetrics.sealRing)
            center.inkText(theme)
        }
        .frame(width: WidgetMetrics.sealDiameter, height: WidgetMetrics.sealDiameter)
        .overlay(alignment: .topTrailing) {
            if case let .agentRunning(_, _, _, jobs) = state {
                StampBadge(count: jobs).offset(x: 8, y: -8)
            }
        }
        .contentShape(Circle())
    }

    @ViewBuilder private var center: some View {
        let letter = Text("h").font(theme.font(.sealLetter))
        switch state {
        case .idle, .agentRunning:
            letter.foregroundStyle(theme.colors.ink)
        case .listening(let level, _):
            VStack(spacing: 1) {
                Text("h").marked(theme).font(theme.font(.sealLetter))
                ListeningSquiggle(level: level, size: CGSize(width: 22, height: 6), stroke: 1.2)
            }
        case .thinking:
            InkDots(dot: 3.5)
        case .speaking:
            letter.foregroundStyle(theme.colors.ink)
                .overlay(alignment: .bottom) { HandUnderline(size: CGSize(width: 18, height: 4)).offset(y: 4) }
        case .error:
            Text("h").wavy(theme).font(theme.font(.sealLetter))
        }
    }
}

/// Type-erased `InsettableShape` so the slip can switch between rounded and tag outlines.
struct AnyInsettableShape: InsettableShape {
    private let base: @Sendable (CGRect) -> Path
    private let insetBy: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape & Sendable>(_ shape: S) {
        base = { shape.path(in: $0) }
        insetBy = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { base(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBy(amount) }
}
