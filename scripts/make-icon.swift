import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let files: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (filename, size) in files {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocusFlipped(false)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: NSSize(width: size, height: size)).fill()

    let fontSize = size * 0.55
    let font = NSFont(name: "Times New Roman Bold", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
    let text = NSAttributedString(string: "d.", attributes: [.font: font, .foregroundColor: NSColor.black])
    let bounds = text.size()
    text.draw(at: NSPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2 - size * 0.03))
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DAYSHIFTIcon", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
}
