import SwiftUI

/// Boards that mirror the mockup canvases. Used by #Previews, the debug gallery window
/// and the snapshot tests, so all three always show the same thing.

/// Margin-Widget-Panel: six widget states + expanded panel, for one appearance.
struct WidgetPanelBoard: View {
    let scheme: ColorScheme
    var highlighter: HighlighterColor = .yellow
    var size: WidgetSize = .medium
    var shape: WidgetShape = .slip
    var showPanel = true

    var body: some View {
        let theme = Theme.resolve(scheme == .dark ? .carbon : .daylight, scheme: scheme, highlighter: highlighter)
        VStack(alignment: .leading, spacing: 32) {
            Text(scheme == .dark ? "Dark — carbon paper" : "Light — daylight paper")
                .textRole(.label, theme).font(theme.font(.heading)).foregroundStyle(theme.colors.ink)
            WidgetStatesGrid(size: size, shape: shape)
            if showPanel {
                PanelSample().frame(maxWidth: .infinity)
            }
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 24).fill(theme.colors.desk))
        .theme(theme)
    }
}

/// 2-column grid of the six states with roman-numeral captions.
struct WidgetStatesGrid: View {
    @Environment(\.theme) private var theme
    var size: WidgetSize = .medium
    var shape: WidgetShape = .slip
    var columns = 2

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 28) {
            ForEach(Array(stride(from: 0, to: WidgetState.samples.count, by: columns)), id: \.self) { row in
                GridRow {
                    ForEach(row..<min(row + columns, WidgetState.samples.count), id: \.self) { i in
                        let (label, state) = WidgetState.samples[i]
                        VStack(alignment: .leading, spacing: 10) {
                            Text(label).textRole(.label, theme).foregroundStyle(theme.colors.muted)
                            WidgetView(state: state, shape: shape, size: size)
                        }
                    }
                }
            }
        }
    }
}

/// The expanded panel with the mockup's sample conversation.
struct PanelSample: View {
    @State private var draft = ""
    var date = Self.mockupDate

    var body: some View {
        ExpandedPanelView(messages: SampleConversation.messages, notes: SampleConversation.notes,
                          workflows: SampleConversation.workflows, modelName: "Gemma 4 local",
                          date: date, draft: $draft)
    }

    /// Sat 10 Oct 2026, the date shown in the mockups.
    static let mockupDate = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 10, day: 10, hour: 12).date!
}

/// Margin-Themes: the four extra themes, every widget state + panel.
struct ExtraThemesBoard: View {
    var themes: [ThemeID] = [.blueprint, .legalPad, .typewriter, .kraft]
    var showPanel = true

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(themes) { id in
                ThemeColumn(theme: Theme.resolve(id), showPanel: showPanel)
            }
        }
    }
}

struct ThemeColumn: View {
    let theme: Theme
    var showPanel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(theme.id.displayName)
                .font(theme.font(theme.type.chrome == .newsreader ? .body(26) : .widgetState(26 / theme.type.stateScale)))
                .fontWeight(theme.id == .blueprint ? .semibold : .medium)
                .textCase(theme.id == .blueprint ? .uppercase : nil)
                .foregroundStyle(theme.colors.ink)
            ForEach(WidgetState.samples, id: \.0) { label, state in
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(FontFactory.font(.newsreader, size: 14, italic: true)).foregroundStyle(theme.colors.muted)
                    WidgetView(state: state)
                }
            }
            if showPanel { PanelSample() }
        }
        .padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 30)
        .background {
            ZStack {
                theme.colors.desk
                TextureView(style: theme.texture)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .theme(theme)
    }
}

/// Margin-Themes › Widget options: shape, size, idle opacity, density.
struct WidgetOptionsBoard: View {
    var scheme: ColorScheme = .light

    var body: some View {
        let theme = Theme.resolve(scheme == .dark ? .carbon : .daylight, scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            Text("Widget options — shape, size, idle opacity, density")
                .font(theme.font(.heading)).italic().foregroundStyle(theme.colors.muted)
            HStack(alignment: .top, spacing: 40) {
                column("Shape") {
                    caption("Slip"); WidgetView(state: .idle, shape: .slip)
                    caption("Index tab — docks to a screen edge"); WidgetView(state: .idle, shape: .indexTab)
                    caption("Seal — smallest footprint"); WidgetView(state: .idle, shape: .seal)
                }
                column("Size") {
                    ForEach(WidgetSize.allCases) { s in
                        let m = WidgetMetrics.of(s)
                        caption("\(s.rawValue) · \(Int(m.width)) × \(Int(m.height))")
                        WidgetView(state: .listening(level: 1, elapsed: 0), size: s)
                    }
                }
                column("Idle opacity (snaps to 100% on hover or voice)") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach([1.0, 0.6, 0.35], id: \.self) { o in
                            HStack(spacing: 12) {
                                WidgetView(state: .idle, size: .small).opacity(o)
                                Text("\(Int(o * 100))%").font(theme.font(.mono(11))).foregroundStyle(Color.white.opacity(0.92))
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.36, green: 0.42, blue: 0.37)))
                }
                column("Density") {
                    ForEach(Density.allCases.reversed()) { d in
                        caption(d.label)
                        DensitySample().theme(Theme.resolve(theme.id, scheme: scheme, density: d.metrics))
                    }
                }
            }
            Divider().opacity(0)
            Text("Seal & index tab, all states").font(theme.font(.label)).italic().foregroundStyle(theme.colors.muted)
            HStack(alignment: .top, spacing: 40) {
                WidgetStatesGrid(shape: .indexTab)
                HStack(spacing: 28) {
                    ForEach(WidgetState.samples, id: \.0) { label, state in
                        VStack(spacing: 10) {
                            caption(String(label.split(separator: " ").last ?? ""))
                            WidgetView(state: state, shape: .seal)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 32)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.colors.desk))
        .theme(theme)
    }

    @ViewBuilder private func column<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallCaps(text: title, size: TypeScale.smallCapsTight)
            content()
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(FontFactory.font(.newsreader, size: 13, italic: true))
            .foregroundStyle(Theme.resolve(.daylight, scheme: scheme).colors.muted)
            .padding(.top, 4)
    }
}

private struct DensitySample: View {
    @Environment(\.theme) private var theme
    var body: some View {
        let d = theme.density
        VStack(alignment: .leading, spacing: d.messageGap) {
            MessageView(message: ChatMessage(.user, "deploy staging"))
            MessageView(message: ChatMessage(.haku, "Waiting for your yes."))
            MessageView(message: ChatMessage(.user, "yes"))
        }
        .padding(.horizontal, d.bodyPaddingH).padding(.vertical, d.bodyPaddingV)
        .frame(width: 220, alignment: .leading)
        .background(theme.colors.paper)
        .overlay(Rectangle().strokeBorder(theme.colors.border, lineWidth: 1))
    }
}

/// Logo, wordmark, app icons and menu-bar glyphs.
struct BrandBoard: View {
    var highlighter: HighlighterColor = .yellow
    var body: some View {
        let light = Theme.resolve(.daylight, highlighter: highlighter)
        let dark = Theme.resolve(.carbon, highlighter: highlighter)
        HStack(alignment: .bottom, spacing: 40) {
            HStack(spacing: 24) {
                CardGlyph(color: light.colors.ink, highlight: light.highlight, highlightTilt: -3, paperLine: light.colors.paper)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ha") + Text("ku").marked(Theme.resolve(.daylight, highlighter: highlighter))
                }
                .font(light.font(.wordmark))
                .tracking(light.tracking(.wordmark))
                .foregroundStyle(light.colors.ink)
                .textRenderer(InkTextRenderer(marking: .band(top: 0.55, bottom: 0.88), markColor: light.highlight,
                                              boxColor: light.colors.ink, errorColor: light.colors.error))
            }
            Spacer()
            AppIconView(theme: light).frame(width: 64, height: 64)
            AppIconView(theme: dark).frame(width: 64, height: 64).theme(dark)
            HStack(spacing: 14) {
                CardGlyph(style: .outlined, color: light.colors.ink).frame(width: 18, height: 18)
                CardGlyph(color: light.colors.ink).frame(width: 18, height: 18)
            }
            .padding(.horizontal, 14).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 8).fill(light.colors.desk))
        }
        .theme(light)
    }
}

/// App icon: paper tile (radius 11/48) with the icon card and tilted highlighter.
struct AppIconView: View {
    let theme: Theme
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 48
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11 * s, style: .continuous).fill(theme.colors.paper)
                if theme.scheme == .light {
                    RoundedRectangle(cornerRadius: 11 * s, style: .continuous).strokeBorder(theme.colors.rule, lineWidth: max(1, s))
                }
                SVGShape(GlyphPaths.iconCard, viewBox: CGSize(width: 48, height: 48)).fill(theme.colors.ink)
                Rectangle().fill(theme.highlight)
                    .frame(width: 20 * s, height: 6 * s)
                    .rotationEffect(.degrees(-3), anchor: UnitPoint(x: 0.5, y: 0.5))
                    .offset(x: 13 * s, y: 22 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Everything on one scrollable page (debug window).
struct DesignGallery: View {
    @Environment(ThemeManager.self) private var manager
    @State private var highlighter: HighlighterColor = .yellow
    @State private var reduceMotion = false

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 48) {
                HStack(spacing: 16) {
                    Picker("Highlighter", selection: $highlighter) {
                        ForEach(HighlighterColor.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(width: 220)
                    Toggle("Static frames (Reduce Motion)", isOn: $reduceMotion)
                }
                BrandBoard(highlighter: highlighter)
                HStack(alignment: .top, spacing: 32) {
                    WidgetPanelBoard(scheme: .light, highlighter: highlighter)
                    WidgetPanelBoard(scheme: .dark, highlighter: highlighter)
                }
                ExtraThemesBoard()
                WidgetOptionsBoard()
            }
            .padding(64)
            .environment(\.motionDisabled, reduceMotion)
        }
        .background(ThemeColors.canvas)
        .environment(\.colorScheme, .light)
    }
}
