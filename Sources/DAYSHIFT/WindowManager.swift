import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private weak var window: NSWindow?
    private weak var tutorialDimmer: NSView?
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

    func setTutorialDimmed(_ dimmed: Bool) {
        guard let window, let frameView = window.contentView?.superview else { return }
        guard dimmed else {
            tutorialDimmer?.removeFromSuperview()
            return
        }

        let titlebarHeight = max(0, frameView.bounds.height - window.contentLayoutRect.height)
        let frame = CGRect(
            x: 0,
            y: frameView.bounds.maxY - titlebarHeight,
            width: frameView.bounds.width,
            height: titlebarHeight
        )
        if let tutorialDimmer {
            tutorialDimmer.frame = frame
            return
        }

        let dimmer = TitlebarDimmerView(frame: frame)
        dimmer.autoresizingMask = [.width, .minYMargin]
        dimmer.wantsLayer = true
        dimmer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.48).cgColor
        frameView.addSubview(dimmer, positioned: .above, relativeTo: nil)
        tutorialDimmer = dimmer
    }

    private final class TitlebarDimmerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

}

struct WindowAccessor: NSViewRepresentable {
    var tutorialDimmed = false

    func makeNSView(context: Context) -> NSView {
        let view = AccessView()
        view.tutorialDimmed = tutorialDimmed
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? AccessView else { return }
        view.tutorialDimmed = tutorialDimmed
        WindowManager.shared.setTutorialDimmed(tutorialDimmed)
    }

    private final class AccessView: NSView {
        var tutorialDimmed = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                WindowManager.shared.attach(window)
                WindowManager.shared.setTutorialDimmed(tutorialDimmed)
            }
        }
    }
}

struct RightClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EventView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EventView)?.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? EventView)?.removeMonitor()
    }

    private final class EventView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { removeMonitor() } else { installMonitor() }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self,
                      event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                    return event
                }
                DispatchQueue.main.async { [weak self] in self?.action?() }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { removeMonitor() }
    }
}

struct OutsideClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EventView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EventView)?.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? EventView)?.removeObservers()
    }

    private final class EventView: NSView {
        var action: (() -> Void)?
        private var mouseMonitor: Any?
        private var resignObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else { return }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if !self.bounds.contains(point) {
                    // Let the clicked control handle its event before closing
                    // the old editor. Opening a new one should win.
                    DispatchQueue.main.async { [weak self] in self?.action?() }
                }
                return event
            }

            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.action?()
            }
        }

        func removeObservers() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
        }

        deinit { removeObservers() }
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
