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
    enum GestureEvent {
        case began
        case changed(CGFloat)
        case ended
        case page(Int)
    }

    let onGesture: (GestureEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EventView()
        view.onGesture = onGesture
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EventView)?.onGesture = onGesture
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? EventView)?.removeMonitor()
    }

    private final class EventView: NSView {
        var onGesture: ((GestureEvent) -> Void)?
        private var monitor: Any?
        private var lastDiscreteEventTime: TimeInterval = 0
        private var gestureIsActive = false
        private var pendingEnd: DispatchWorkItem?

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

                if !event.hasPreciseScrollingDeltas {
                    let now = ProcessInfo.processInfo.systemUptime
                    if abs(event.scrollingDeltaY) > 0.1, now - self.lastDiscreteEventTime >= 0.24 {
                        self.onGesture?(.page(event.scrollingDeltaY < 0 ? 1 : -1))
                    }
                    self.lastDiscreteEventTime = now
                    return nil
                }

                self.pendingEnd?.cancel()
                if !self.gestureIsActive {
                    self.gestureIsActive = true
                    self.onGesture?(.began)
                }
                self.onGesture?(.changed(event.scrollingDeltaY))

                let phaseFinished = event.phase.contains(.ended) || event.phase.contains(.cancelled)
                let momentumFinished = event.momentumPhase.contains(.ended)
                if phaseFinished || momentumFinished {
                    // A momentum sequence can begin immediately after the finger
                    // phase ends. The tiny debounce joins both into one gesture.
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.gestureIsActive else { return }
                        self.gestureIsActive = false
                        self.onGesture?(.ended)
                    }
                    self.pendingEnd = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.055, execute: work)
                }
                return nil
            }
        }

        func removeMonitor() {
            pendingEnd?.cancel()
            pendingEnd = nil
            gestureIsActive = false
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
