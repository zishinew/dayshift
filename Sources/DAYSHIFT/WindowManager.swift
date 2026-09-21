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

    func hideScrollers() {
        DispatchQueue.main.async { [weak self] in
            guard let root = self?.window?.contentView else { return }
            self?.hideScrollers(in: root)
        }
    }

    private func hideScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.isHidden = true
            scrollView.autohidesScrollers = true
        }
        for child in view.subviews {
            hideScrollers(in: child)
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

/// Keeps SwiftUI's paged scroll interaction while removing macOS's persistent
/// scroller chrome from this intentionally bare calendar.
struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AccessView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AccessView)?.configureScrollViews()
    }

    private final class AccessView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureScrollViews()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollViews()
        }

        func configureScrollViews() {
            DispatchQueue.main.async { [weak self] in
                guard let root = self?.window?.contentView else { return }
                self?.hideScrollers(in: root)
            }
        }

        private func hideScrollers(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScroller?.isHidden = true
                scrollView.horizontalScroller?.isHidden = true
                scrollView.autohidesScrollers = true
            }
            for child in view.subviews {
                hideScrollers(in: child)
            }
        }
    }
}
