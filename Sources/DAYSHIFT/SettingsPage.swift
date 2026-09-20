import SwiftUI

@MainActor
struct SettingsPage: View {
    @Environment(AppearanceSettings.self) private var appearance
    private let textPalette = [
        AppearanceSwatch("black", .black),
        AppearanceSwatch("charcoal", Color(white: 0.2)),
        AppearanceSwatch("gray", Color(white: 0.48)),
        AppearanceSwatch("white", .white)
    ]
    private let backgroundPalette = [
        AppearanceSwatch("white", .white),
        AppearanceSwatch("paper", Color(white: 0.96)),
        AppearanceSwatch("gray", Color(white: 0.86)),
        AppearanceSwatch("graphite", Color(white: 0.13)),
        AppearanceSwatch("black", .black)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("settings")
                    .font(.custom(appearance.fontName, size: appearance.scaled(24)))
                    .padding(.bottom, 30)

                settingSection("appearance") {
                    colorRow("text", color: Binding(get: { appearance.textColor }, set: { appearance.textColor = $0 }), palette: textPalette)
                    colorRow("background", color: Binding(get: { appearance.backgroundColor }, set: { appearance.backgroundColor = $0 }), palette: backgroundPalette)
                    fontRow
                    sliderRow("text size", value: Binding(get: { appearance.textSize }, set: { appearance.textSize = $0 }), range: 14...25, valueLabel: "\(Int(appearance.textSize))")
                    sliderRow("row spacing", value: Binding(get: { appearance.rowSpacing }, set: { appearance.rowSpacing = $0 }), range: 4...18, valueLabel: "\(Int(appearance.rowSpacing))")
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
        .tint(appearance.textColor)
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

    private func colorRow(_ title: String, color: Binding<Color>, palette: [AppearanceSwatch]) -> some View {
        HStack {
            Text(title)
                .font(.custom(appearance.fontName, size: appearance.scaled(16)))
            Spacer()
            HStack(spacing: 9) {
                ForEach(palette) { swatch in
                    PaletteSwatchButton(
                        swatch: swatch,
                        selected: appearance.matches(color.wrappedValue, swatch.color),
                        borderColor: appearance.textColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            color.wrappedValue = swatch.color
                        }
                    }
                }
            }
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
                .tint(appearance.textColor)
            Text(valueLabel)
                .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

private struct AppearanceSwatch: Identifiable {
    let name: String
    let color: Color
    var id: String { name }

    init(_ name: String, _ color: Color) {
        self.name = name
        self.color = color
    }
}

private struct PaletteSwatchButton: View {
    let swatch: AppearanceSwatch
    let selected: Bool
    let borderColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2)
                .fill(swatch.color)
                .frame(width: 16, height: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(borderColor.opacity(selected ? 1 : 0.28), lineWidth: selected ? 2 : 1)
                }
                .scaleEffect(isHovered ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .help(swatch.name)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
