import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top panel that never steals focus.
final class PetPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.fittingSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that turns mouse input into click / drag / right-click callbacks.
final class PetHostingView<Content: View>: NSHostingView<Content> {
    var onClick: ((NSEvent) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onMoved: (() -> Void)?

    private var downLocation: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downLocation = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downLocation, let window else { return }
        let p = event.locationInWindow
        if !dragged, hypot(p.x - start.x, p.y - start.y) < 3 { return }
        dragged = true
        var origin = window.frame.origin
        origin.x += p.x - start.x
        origin.y += p.y - start.y
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onMoved?() } else { onClick?(event) }
        downLocation = nil
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

enum PetPlacement {
    static let key = "petOrigin"

    static func restore(_ window: NSWindow) {
        if let s = UserDefaults.standard.string(forKey: key) {
            window.setFrameOrigin(NSPointFromString(s))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: v.maxX - window.frame.width - 24, y: v.minY + 12))
        }
        clamp(window)
    }

    static func save(_ window: NSWindow) {
        clamp(window)
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: key)
    }

    /// Keeps the pet fully on a visible screen (after drags, unplugged monitors, …).
    static func clamp(_ window: NSWindow) {
        let f = window.frame
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let target = screens.first { $0.visibleFrame.intersects(f) }
            ?? screens.min { distance($0.visibleFrame, f) < distance($1.visibleFrame, f) }!
        let v = target.visibleFrame
        var o = f.origin
        o.x = min(max(o.x, v.minX), v.maxX - f.width)
        o.y = min(max(o.y, v.minY), v.maxY - f.height)
        if o != f.origin { window.setFrameOrigin(o) }
    }

    private static func distance(_ a: NSRect, _ b: NSRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}
