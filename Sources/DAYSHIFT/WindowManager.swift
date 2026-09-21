import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private weak var window: NSWindow?
    private var configured = false

    func attach(_ window: NSWindow) {
        self.window = window
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.toolbar?.showsBaselineSeparator = false
        window.isOpaque = true
        window.backgroundColor = .white

        guard !configured else { return }
        configured = true
        DispatchQueue.main.async {
            // Maximize within the normal macOS window frame. This fills the
            // usable screen area while preserving the title bar and controls.
            if !window.isZoomed {
                window.performZoom(nil)
            }
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

struct ScrollWheelPager: NSViewRepresentable {
    let onPage: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EventView()
        view.onPage = onPage
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EventView)?.onPage = onPage
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? EventView)?.removeMonitor()
    }

    private final class EventView: NSView {
        var onPage: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulatedDelta: CGFloat = 0
        private var pageTriggered = false
        private var lastPageTime: TimeInterval = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else {
                installMonitor()
            }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                    return event
                }

                let phase = event.phase
                let momentumPhase = event.momentumPhase
                if phase.contains(.began) {
                    self.accumulatedDelta = 0
                    self.pageTriggered = false
                }

                // The initiating gesture changes one page. Momentum belongs to
                // that same gesture and must not advance through more months.
                if !momentumPhase.isEmpty {
                    return nil
                }

                if phase.isEmpty {
                    if abs(event.scrollingDeltaY) > 0.1 {
                        self.triggerPage(event.scrollingDeltaY < 0 ? 1 : -1)
                    }
                    return nil
                }

                self.accumulatedDelta += event.scrollingDeltaY
                if !self.pageTriggered, abs(self.accumulatedDelta) >= 8 {
                    self.pageTriggered = true
                    self.triggerPage(self.accumulatedDelta < 0 ? 1 : -1)
                }

                if phase.contains(.ended) || phase.contains(.cancelled) {
                    self.accumulatedDelta = 0
                    self.pageTriggered = false
                }
                return nil
            }
        }

        private func triggerPage(_ direction: Int) {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPageTime >= 0.38 else { return }
            lastPageTime = now
            onPage?(direction)
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
