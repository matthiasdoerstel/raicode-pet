import AppKit
import SwiftUI

/// A menu bar dropdown on real Liquid Glass (`NSGlassEffectView`), like Weather or Control Center:
/// borderless, rounded, content sitting directly on the glass. Closes on an outside click or Escape.
@MainActor
final class GlassDropdown {
    private let panel: NSPanel
    private var monitors: [Any] = []
    /// The status bar window; clicks there are the button's own toggle, not an outside click.
    private weak var anchorWindow: NSWindow?
    var isShown: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
    }

    private func setContent(_ view: NSView) {
        if #available(macOS 26.0, *) {
            let glass = (panel.contentView as? NSGlassEffectView) ?? NSGlassEffectView()
            glass.cornerRadius = 22
            glass.contentView = view
            panel.contentView = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 12
            blur.layer?.masksToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                view.topAnchor.constraint(equalTo: blur.topAnchor),
                view.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            panel.contentView = blur
        }
    }

    /// Shows `content` under the status item button.
    func show<Content: View>(_ content: Content, below button: NSStatusBarButton) {
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        setContent(host)
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        anchorWindow = buttonWindow
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
        watchForDismissal()
    }

    func close() {
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func watchForDismissal() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) { monitors.append(m) }
        // Clicks in our own windows outside the panel, and Escape.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
                return event
            }
            if event.window !== self.panel, event.window !== self.anchorWindow { self.close() }
            return event
        }) { monitors.append(m) }
    }
}
