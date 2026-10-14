import AppKit
import Combine
import RaicodePetCore

/// Drives which animation and frame the pet shows.
@MainActor
final class PetController: ObservableObject {
    @Published private(set) var art: PetArt
    @Published private(set) var frame: CGImage?
    @Published private(set) var petState: PetState = .idle

    private var animation: PetAnimation = .idle
    private var oneShot: PetAnimation?
    private var frameIndex = 0
    private var timer: Timer?
    private var nextIdleVariety = Date().addingTimeInterval(25)
    /// How long the pet stays happy after a task; then it dozes off while "Done!" stays up.
    private let happyDuration: TimeInterval = 15
    private var doneSince: Date?

    /// The pet's window, for working out where the pointer is relative to the pet.
    weak var window: NSWindow?
    /// Set while the pet is dragged; overrides everything else.
    private var walk: PetAnimation?
    private var lastPointer: NSPoint?
    private var pointerMovedAt = Date.distantPast
    /// The pet watches the pointer while it moves within this distance…
    private let lookRange: CGFloat = 500
    /// …outside this deadzone around its face…
    private let lookDeadzone: CGFloat = 45
    /// …and for this long after it stops moving.
    private let lookLinger: TimeInterval = 2.5

    init(art: PetArt) {
        self.art = art
        restart()
    }

    func setArt(_ art: PetArt) {
        self.art = art
        restart()
    }

    func show(_ state: PetState) {
        guard state != petState else { return }
        let previous = petState
        petState = state
        doneSince = state == .done ? Date() : nil
        if state == .done && previous != .done {
            play(.celebrate)
        } else {
            oneShot = nil
            restart()
        }
    }

    /// Plays an animation once, then returns to the state loop.
    func play(_ animation: PetAnimation) {
        oneShot = animation
        restart()
    }

    /// Called on every drag step with the horizontal movement.
    func dragged(dx: CGFloat) {
        guard art.canWalk, !reduceMotion else { return }
        let direction: PetAnimation? = dx > 0.5 ? .walkRight : dx < -0.5 ? .walkLeft : walk
        guard let direction, direction != walk else { return }
        let first = walk == nil
        walk = direction
        // Keep the stride going when only the direction flips.
        if first { frameIndex = 0 }
        animation = direction
        tick(advance: false)
    }

    func dragEnded() {
        guard walk != nil else { return }
        walk = nil
        restart()
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func loopAnimation() -> PetAnimation {
        switch petState {
        case .idle: return .idle
        case .working: return .working
        case .waiting: return .waiting
        case .done:
            if let since = doneSince, Date().timeIntervalSince(since) > happyDuration { return .idle }
            return .done
        case .failed: return .failed
        }
    }

    private func restart() {
        animation = walk ?? oneShot ?? loopAnimation()
        frameIndex = 0
        tick(advance: false)
    }

    private func tick(advance: Bool) {
        timer?.invalidate()
        var frames = art.frames(animation)
        if advance { frameIndex += 1 }

        if animation == .idle, oneShot == nil, let pose = lookPose() {
            frameIndex = 0
            frame = pose
            schedule(after: 0.1, advance: false)
            return
        }

        if frameIndex >= frames.count {
            if walk == nil, oneShot != nil || animation == .stretch || animation == .lookAround || animation == .done {
                oneShot = nil
                animation = loopAnimation()
                frames = art.frames(animation)
            }
            frameIndex = 0
        }

        // Now and then, an idle pet stretches or looks around.
        if animation == .idle, frameIndex == 0, Date() > nextIdleVariety, !reduceMotion {
            nextIdleVariety = Date().addingTimeInterval(.random(in: 20...45))
            // Pick the variation once, so the whole sequence plays from one row.
            animation = Bool.random() ? .stretch : .lookAround
            frames = art.frames(animation)
        }

        guard !frames.isEmpty else { frame = nil; return }
        frame = frames[min(frameIndex, frames.count - 1)]

        // Reduced motion shows a still pet, but keeps a slow check so it can still look at the pointer.
        if reduceMotion && oneShot == nil {
            if animation == .idle && art.canLook { schedule(after: 0.25, advance: false) }
            return
        }
        schedule(after: art.frameDuration(animation, index: frameIndex), advance: true)
    }

    private func schedule(after interval: TimeInterval, advance: Bool) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick(advance: advance) }
        }
    }

    /// The look pose facing the pointer, while the pointer is moving near the pet.
    private func lookPose() -> CGImage? {
        guard art.canLook, let window else { return nil }
        let pointer = NSEvent.mouseLocation
        if let last = lastPointer, hypot(pointer.x - last.x, pointer.y - last.y) > 1 {
            pointerMovedAt = Date()
        }
        lastPointer = pointer
        guard Date().timeIntervalSince(pointerMovedAt) < lookLinger else { return nil }

        // The sprite sits at the bottom of the window; aim from roughly its face.
        let size = art.displaySize
        let face = NSPoint(x: window.frame.midX, y: window.frame.minY + size.height * 0.65)
        let dx = pointer.x - face.x, dy = pointer.y - face.y
        let distance = hypot(dx, dy)
        guard distance > lookDeadzone, distance < lookRange else { return nil }
        return art.lookFrame(LookDirection.index(dx: dx, dy: dy))
    }
}
