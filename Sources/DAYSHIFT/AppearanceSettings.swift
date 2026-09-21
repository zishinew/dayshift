import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppearanceSettings {
    static let fontOptions = ["Times New Roman", "Baskerville", "Georgia", "Palatino"]

    var textColor: Color { didSet { save() } }
    var backgroundColor: Color { didSet { save() } }
    var fontName: String { didSet { save() } }
    var textSize: Double { didSet { save() } }
    var rowSpacing: Double { didSet { save() } }
    var showCommandHints: Bool { didSet { save() } }
    var usesScrollingCalendar: Bool { didSet { save() } }

    init() {
        let defaults = UserDefaults.standard
        textColor = Self.color(forKey: "textColor", defaults: defaults) ?? .black
        backgroundColor = Self.color(forKey: "backgroundColor", defaults: defaults) ?? .white
        fontName = defaults.string(forKey: "fontName") ?? "Times New Roman"
        textSize = defaults.object(forKey: "textSize") == nil ? 18 : defaults.double(forKey: "textSize")
        rowSpacing = defaults.object(forKey: "rowSpacing") == nil ? 9 : defaults.double(forKey: "rowSpacing")
        showCommandHints = defaults.object(forKey: "showCommandHints") == nil ? true : defaults.bool(forKey: "showCommandHints")
        usesScrollingCalendar = defaults.object(forKey: "usesScrollingCalendar") == nil ? true : defaults.bool(forKey: "usesScrollingCalendar")
    }

    func scaled(_ base: CGFloat) -> CGFloat {
        base * CGFloat(textSize / 18)
    }

    func reset() {
        textColor = .black
        backgroundColor = .white
        fontName = "Times New Roman"
        textSize = 18
        rowSpacing = 9
        showCommandHints = true
        usesScrollingCalendar = true
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(fontName, forKey: "fontName")
        defaults.set(textSize, forKey: "textSize")
        defaults.set(rowSpacing, forKey: "rowSpacing")
        defaults.set(showCommandHints, forKey: "showCommandHints")
        defaults.set(usesScrollingCalendar, forKey: "usesScrollingCalendar")
        defaults.set(colorData(textColor), forKey: "textColor")
        defaults.set(colorData(backgroundColor), forKey: "backgroundColor")
    }

    private static func color(forKey key: String, defaults: UserDefaults) -> Color? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredColor.self, from: data) else { return nil }
        return Color(red: stored.red, green: stored.green, blue: stored.blue, opacity: stored.alpha)
    }

    private func colorData(_ color: Color) -> Data? {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        let stored = StoredColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
        return try? JSONEncoder().encode(stored)
    }
}

private struct StoredColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}
