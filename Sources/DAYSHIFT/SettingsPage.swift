import SwiftUI

@MainActor
struct SettingsPage: View {
    @Environment(AppearanceSettings.self) private var appearance
    private let serif = "Times New Roman"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("settings")
                    .font(.custom(appearance.fontName, size: appearance.scaled(24)))
                    .padding(.bottom, 30)

                settingSection("appearance") {
                    colorRow("text", color: Binding(get: { appearance.textColor }, set: { appearance.textColor = $0 }))
                    colorRow("background", color: Binding(get: { appearance.backgroundColor }, set: { appearance.backgroundColor = $0 }))
                    fontRow
                    sliderRow("text size", value: Binding(get: { appearance.textSize }, set: { appearance.textSize = $0 }), range: 14...25, valueLabel: "(Int(appearance.textSize))")
                    sliderRow("row spacing", value: Binding(get: { appearance.rowSpacing }, set: { appearance.rowSpacing = $0 }), range: 4...18, valueLabel: "(Int(appearance.rowSpacing))")
                }

                settingSection("behavior") {
                    Toggle(isOn: Binding(get: { appearance.showCommandHints }, set: { appearance.showCommandHints = $0 })) {
                        Text("show command hints")
                            .font(.custom(appearance.fontName, size: appearance.scaled(15)))
                    }
                    .toggleStyle(.checkbox)
                }

                Button("reset appearance") { withAnimation(.easeInOut(duration: 0.15)) { appearance.reset() } }
                    .font(.custom(appearance.fontName, size: appearance.scaled(14)))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 34)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(appearance.backgroundColor)
        .foregroundStyle(appearance.textColor)
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.custom(appearance.fontName, size: appearance.scaled(15)))
                .foregroundStyle(appearance.textColor.opacity(0.62))
            content()
        }
        .padding(.bottom, 30)
    }

    private func colorRow(_ title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .font(.custom(appearance.fontName, size: appearance.scaled(16)))
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private var fontRow: some View {
        HStack {
            Text("font")
                .font(.custom(appearance.fontName, size: appearance.scaled(16)))
            Spacer()
            Menu {
                ForEach(AppearanceSettings.fontOptions, id: \.self) { font in
                    Button {
                        appearance.fontName = font
                    } label: {
                        Text(font).font(.custom(font, size: 14))
                    }
                }
            } label: {
                Text(appearance.fontName.lowercased())
                    .font(.custom(appearance.fontName, size: appearance.scaled(15)))
                    .foregroundStyle(appearance.textColor)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueLabel: String) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.custom(appearance.fontName, size: appearance.scaled(16)))
            Slider(value: value, in: range)
                .frame(maxWidth: 190)
            Text(valueLabel)
                .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
