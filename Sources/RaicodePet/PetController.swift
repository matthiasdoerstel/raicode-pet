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
        animation = oneShot ?? loopAnimation()
        frameIndex = 0
        tick(advance: false)
    }

    private func tick(advance: Bool) {
        timer?.invalidate()
        var frames = art.frames(animation)
        if advance { frameIndex += 1 }

        if frameIndex >= frames.count {
            if oneShot != nil || animation == .stretch || animation == .lookAround || animation == .done {
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

        if reduceMotion && oneShot == nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: art.frameDuration(animation), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick(advance: true) }
        }
    }
}
