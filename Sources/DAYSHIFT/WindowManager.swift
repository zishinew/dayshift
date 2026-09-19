import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private weak var window: NSWindow?
    private var configured = false

    func attach(_ window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .white

        guard !configured else { return }
        configured = true
        DispatchQueue.main.async {
            if !(window.styleMask.contains(.fullScreen)) {
                window.toggleFullScreen(nil)
            }
        }
    }

    func setCompact(_ compact: Bool) {
        guard let window else { return }
        if compact {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let screen = window.screen ?? NSScreen.main else { return }
                let visible = screen.visibleFrame
                let width: CGFloat = 340
                let frame = NSRect(
                    x: visible.maxX - width - 18,
                    y: visible.minY + 18,
                    width: width,
                    height: visible.height - 36
                )
                window.setFrame(frame, display: true, animate: true)
                window.level = .floating
                window.collectionBehavior.insert(.canJoinAllSpaces)
            }
        } else {
            window.level = .normal
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.toggleFullScreen(nil)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AccessView() }
    func updateNSView(_ nsView: NSView, context: Context) { }

    private final class AccessView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowManager.shared.attach(window) }
        }
    }
}
