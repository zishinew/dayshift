import AppKit
import SwiftUI

@MainActor
struct SettingsPage: View {
    @Environment(AppearanceSettings.self) private var appearance
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("settings")
                    .font(.custom(appearance.fontName, size: appearance.scaled(24)))
                    .padding(.bottom, 30)

                settingSection("appearance") {
                    ThemedColorPickerRow(title: "text", color: Binding(get: { appearance.textColor }, set: { appearance.textColor = $0 }), fontName: appearance.fontName, fontSize: appearance.scaled(16), borderColor: appearance.textColor)
                    ThemedColorPickerRow(title: "background", color: Binding(get: { appearance.backgroundColor }, set: { appearance.backgroundColor = $0 }), fontName: appearance.fontName, fontSize: appearance.scaled(16), borderColor: appearance.textColor)
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

private struct ThemedColorPickerRow: View {
    let title: String
    @Binding var color: Color
    let fontName: String
    let fontSize: CGFloat
    let borderColor: Color
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.custom(fontName, size: fontSize))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 17, height: 17)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(borderColor.opacity(0.6), lineWidth: 1)
                        }
                        .scaleEffect(isHovered ? 1.12 : 1)
                }
                .buttonStyle(.plain)
                .help("choose \(title) color")
                .accessibilityLabel("Choose \(title) color")
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
            }

            if isExpanded {
                ColorWheelPicker(color: $color, borderColor: borderColor, fontName: fontName)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            }
        }
    }
}

private struct ColorWheelPicker: View {
    @Binding var color: Color
    let borderColor: Color
    let fontName: String
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double

    init(color: Binding<Color>, borderColor: Color, fontName: String) {
        _color = color
        self.borderColor = borderColor
        self.fontName = fontName
        let nsColor = NSColor(color.wrappedValue).usingColorSpace(.deviceRGB) ?? .black
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        _hue = State(initialValue: Double(hue))
        _saturation = State(initialValue: Double(saturation))
        _brightness = State(initialValue: Double(brightness))
    }

    var body: some View {
        HStack(spacing: 16) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let radius = size / 2
                let selection = CGPoint(
                    x: radius + cos(hue * .pi * 2) * saturation * radius,
                    y: radius + sin(hue * .pi * 2) * saturation * radius
                )

                Canvas { context, _ in
                    let center = CGPoint(x: radius, y: radius)
                    for step in 0..<360 {
                        var wedge = Path()
                        wedge.move(to: center)
                        wedge.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(Double(step)),
                            endAngle: .degrees(Double(step + 1)),
                            clockwise: false
                        )
                        wedge.closeSubpath()
                        context.fill(wedge, with: .color(Color(hue: Double(step) / 360, saturation: 1, brightness: 1)))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: radius)
                        .clipShape(Circle())
                }
                .overlay {
                    Circle()
                        .stroke(borderColor.opacity(0.36), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .position(selection)
                }
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    updateColor(at: value.location, radius: radius)
                })
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                Text("brightness")
                    .font(.custom(fontName, size: 12))
                    .foregroundStyle(borderColor.opacity(0.62))
                Slider(value: Binding(
                    get: { brightness },
                    set: { brightness = $0; updateSelectedColor() }
                ), in: 0...1)
                .tint(Color(hue: hue, saturation: saturation, brightness: max(brightness, 0.1)))
                Text("drag the wheel")
                    .font(.custom(fontName, size: 11))
                    .foregroundStyle(borderColor.opacity(0.52))
            }
            .frame(width: 118, alignment: .leading)
        }
        .padding(.top, 1)
    }

    private func updateColor(at location: CGPoint, radius: CGFloat) {
        let x = location.x - radius
        let y = location.y - radius
        hue = (atan2(y, x) + .pi * 2).truncatingRemainder(dividingBy: .pi * 2) / (.pi * 2)
        saturation = min(1, sqrt(x * x + y * y) / radius)
        updateSelectedColor()
    }

    private func updateSelectedColor() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
