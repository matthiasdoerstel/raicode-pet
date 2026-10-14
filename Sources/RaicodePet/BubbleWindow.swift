import AppKit
import SwiftUI

/// What the speech bubble shows. `nil` means no bubble.
struct BubbleSpec: Equatable {
    var title: String
    var message: String
    var tint: NSColor?
}

/// The speech bubble as its own borderless window on real Liquid Glass, built like `GlassDropdown`:
/// the `NSGlassEffectView` *is* the window's content view. Glass nested inside the pet's large
/// transparent SwiftUI window rendered as a flat frosted fill — no tint, no rim, no lensing.
/// Attached as a child window, so it follows the pet when dragged.
@MainActor
final class BubbleWindow {
    private let panel: NSPanel
    private let glass = ForwardingGlassView()
    private let host = NSHostingView(rootView: BubbleLabel(title: "", message: ""))
    private weak var parent: NSWindow?
    private var spec: BubbleSpec?

    static let cornerRadius: CGFloat = 12
    static let maxWidth = PetView.width - 16

    /// `eventTarget` receives clicks, drags and right-clicks on the bubble, so it behaves like the pet.
    init(parent: NSWindow, eventTarget: NSView) {
        self.parent = parent
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the window shadow draws a hairline outline around the glass
        panel.level = parent.level
        panel.collectionBehavior = parent.collectionBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = host
        glass.eventTarget = eventTarget
        panel.contentView = glass

        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: parent,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func update(_ new: BubbleSpec?) {
        spec = new
        guard let new else { return hide() }
        host.rootView = BubbleLabel(title: new.title, message: new.message)
        // Regular glass only tints in the key window, and the bubble must never take focus.
        // Clear glass keeps its tint in a background window, so tinted states use that.
        glass.style = new.tint == nil ? .regular : .clear
        glass.tintColor = new.tint
        reposition()
        show()
    }

    /// Call after the pet window is shown or hidden (quiet mode, Hide Pet).
    func syncVisibility() {
        if spec != nil, parent?.isVisible == true { show() } else { panel.orderOut(nil) }
    }

    /// Always fades to fully visible — also when a fade-out is still running, which would otherwise
    /// finish and leave an invisible bubble behind (a nil spec followed quickly by a new one).
    private func show() {
        guard let parent, parent.isVisible else { return }
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.spec == nil else { return }
                self.parent?.removeChildWindow(self.panel)
                self.panel.orderOut(nil)
            }
        })
    }

    /// Bottom-centred in the bubble strip at the top of the pet window.
    private func reposition() {
        guard let parent else { return }
        var size = host.fittingSize
        size.width = min(size.width, Self.maxWidth)
        let f = parent.frame
        let stripBottom = f.maxY - PetView.bubbleHeight
        panel.setFrame(NSRect(x: (f.midX - size.width / 2).rounded(), y: stripBottom,
                              width: size.width, height: size.height), display: true)
    }
}

struct BubbleLabel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: BubbleWindow.maxWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Glass that hands mouse input to the pet's view, so the bubble can be clicked and dragged like the pet.
final class ForwardingGlassView: NSGlassEffectView {
    weak var eventTarget: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { eventTarget?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { eventTarget?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { eventTarget?.mouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) { eventTarget?.rightMouseDown(with: event) }
}
