import SwiftUI

// Design checkpoint previews. Each mirrors a canvas in design/mockups.

#Preview("Widget states · light", traits: .sizeThatFitsLayout) {
    WidgetPanelBoard(scheme: .light, showPanel: false).padding()
}

#Preview("Widget states · dark", traits: .sizeThatFitsLayout) {
    WidgetPanelBoard(scheme: .dark, showPanel: false).padding()
}

#Preview("Widget states · reduced motion", traits: .sizeThatFitsLayout) {
    HStack(alignment: .top, spacing: 32) {
        WidgetPanelBoard(scheme: .light, showPanel: false)
        WidgetPanelBoard(scheme: .dark, showPanel: false)
    }
    .environment(\.motionDisabled, true)
    .padding()
}

#Preview("Expanded panel · light", traits: .sizeThatFitsLayout) {
    PanelSample().theme(.resolve(.daylight)).padding(40).background(Theme.resolve(.daylight).colors.desk)
}

#Preview("Expanded panel · dark", traits: .sizeThatFitsLayout) {
    PanelSample().theme(.resolve(.carbon)).padding(40).background(Theme.resolve(.carbon).colors.desk)
}

#Preview("Margin board · light + dark", traits: .sizeThatFitsLayout) {
    HStack(alignment: .top, spacing: 32) {
        WidgetPanelBoard(scheme: .light)
        WidgetPanelBoard(scheme: .dark)
    }
    .padding(64)
    .background(ThemeColors.canvas)
}

#Preview("Highlighter colors", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(HighlighterColor.allCases) { h in
            HStack(spacing: 24) {
                WidgetView(state: .listening(level: 1, elapsed: 0)).theme(.resolve(.daylight, highlighter: h))
                WidgetView(state: .listening(level: 1, elapsed: 0)).theme(.resolve(.carbon, highlighter: h))
            }
        }
    }
    .padding(40)
    .background(ThemeColors.canvas)
}

#Preview("Extra themes", traits: .sizeThatFitsLayout) {
    ExtraThemesBoard().padding(64).background(ThemeColors.canvas)
}

#Preview("Widget options", traits: .sizeThatFitsLayout) {
    WidgetOptionsBoard().padding(64).background(ThemeColors.canvas)
}

#Preview("Brand", traits: .sizeThatFitsLayout) {
    BrandBoard().padding(64).background(ThemeColors.canvas)
}
