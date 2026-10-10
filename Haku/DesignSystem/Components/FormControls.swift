import SwiftUI

/// `.seg`: bordered segmented control, selected segment on paper2 in bold.
struct InkSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(FontFactory.font(theme.type.ui, size: TypeScale.ui, weight: on ? .bold : .regular))
                        .foregroundStyle(on ? theme.colors.ink : theme.colors.muted)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.s8)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(on ? theme.colors.paper2 : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(theme.colors.rule).frame(width: 1) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: theme.chrome.squareCorners ? 0 : Radii.button))
        .overlay(RoundedRectangle(cornerRadius: theme.chrome.squareCorners ? 0 : Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// `.chk`: 15 pt checkbox with sans 13 label.
struct InkCheckbox: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var isOn: Bool
    var muted = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Spacing.s8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(isOn ? theme.colors.ink : theme.colors.paper)
                    RoundedRectangle(cornerRadius: 2).strokeBorder(isOn ? theme.colors.ink : theme.colors.muted, lineWidth: 1)
                    if isOn {
                        Path { p in p.move(to: CGPoint(x: 3.5, y: 7.5)); p.addLine(to: CGPoint(x: 6.5, y: 10.5)); p.addLine(to: CGPoint(x: 11.5, y: 4.5)) }
                            .stroke(theme.colors.paper, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: 15, height: 15)
                Text(title).textRole(.ui, theme).foregroundStyle(muted ? theme.colors.muted : theme.colors.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// `.sw`: 32×18 switch, ink when on.
struct InkSwitch: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.colors.ink : theme.colors.rule)
                Circle().fill(theme.colors.paper).frame(width: 14, height: 14).padding(2)
            }
            .frame(width: 32, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// `.in`: 30 pt mono input on paper2.
struct InkTextField: View {
    @Environment(\.theme) private var theme
    var placeholder: String = ""
    @Binding var text: String
    var mono = true

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? theme.font(.mono(TypeScale.monoInput)) : theme.font(.ui))
            .foregroundStyle(theme.colors.ink)
            .padding(.horizontal, Spacing.s10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.paper2))
            .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
    }
}

/// `.sel`: a menu styled like the mockup's select.
struct InkPicker<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in Button(label(o)) { selection = o } }
        } label: {
            HStack {
                Text(label(selection)).textRole(.ui, theme).foregroundStyle(theme.colors.ink).lineLimit(1)
                Spacer(minLength: 4)
                Text("▾").font(theme.font(.ui)).foregroundStyle(theme.colors.muted)
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Radii.button).fill(theme.colors.paper2))
            .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// `.kbd` inside buttons: tiny mono cap, current color, 75% opacity.
struct KbdHint: View {
    @Environment(\.theme) private var theme
    let key: String
    var body: some View {
        Text(key)
            .font(theme.font(.monoMedium(10)))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(.foreground, lineWidth: 1))
            .opacity(0.75)
    }
}

/// Small squiggle used on the voice line of slips (viewBox 36×16).
struct VoiceSquiggle: View {
    @Environment(\.theme) private var theme
    var active = true
    var body: some View {
        MotionClock { t in
            SVGShape("M1 8 C4 2, 6 14, 9 8 S14 2, 17 8 S22 14, 25 8 S30 4, 35 8", viewBox: CGSize(width: 36, height: 16))
                .trim(from: 0, to: (active ? t : nil).map { Motion.writeProgress(time: $0, period: Motion.writePeriod) } ?? 1)
                .stroke(theme.colors.ink, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .frame(width: 36, height: 16)
        .accessibilityHidden(true)
    }
}

/// `.var`: dashed blue chip used for template variables.
struct VariableChip: View {
    @Environment(\.theme) private var theme
    let name: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(name).font(theme.font(.mono(TypeScale.monoLog))).foregroundStyle(theme.colors.blueInk)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: Radii.button).strokeBorder(theme.colors.blueInk, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .buttonStyle(.plain)
    }
}
