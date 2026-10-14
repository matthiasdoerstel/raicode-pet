import RaicodePetCore
import SwiftUI

struct PetView: View {
    @ObservedObject var pet: PetController
    @ObservedObject var store: SessionStore
    /// The bubble lives in its own glass window (`BubbleWindow`); this view only reserves its space.
    var onBubble: (BubbleSpec?) -> Void = { _ in }

    static let bubbleHeight: CGFloat = 64
    static let width: CGFloat = 200

    var body: some View {
        // Ticks so "needs you! · 4 min" keeps counting while the bubble is up.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let bubbleText = bubbleText(now: now)
        return VStack(spacing: 2) {
            Color.clear
                .frame(height: Self.bubbleHeight)

            sprite(label: accessibilityText(bubbleText))
                .frame(width: pet.art.displaySize.width, height: pet.art.displaySize.height)
        }
        .frame(width: Self.width)
        .overlay(alignment: .bottom) {
            if pet.petCount > 0 {
                HeartsBurst(originHeight: pet.art.displaySize.height * 0.7)
                    .id(pet.petCount)  // a fresh burst per pet
            }
        }
        .onChange(of: bubbleSpec(bubbleText), initial: true) { _, spec in onBubble(spec) }
    }

    private func bubbleSpec(_ text: (title: String, message: String)?) -> BubbleSpec? {
        text.map { BubbleSpec(title: $0.title, message: $0.message, tint: tint) }
    }

    @ViewBuilder private func sprite(label: String) -> some View {
        if let frame = pet.frame {
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(pet.art.smoothScaling ? .high : .none)
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(label)
        }
    }

    private var focus: SessionRecord? {
        store.sessions.first { $0.state == store.state }
    }

    private func bubbleText(now: Date) -> (title: String, message: String)? {
        guard let s = focus else { return nil }
        let message: String
        switch store.state {
        case .idle: return nil
        case .working: message = s.detail.map { "working… \($0)" } ?? "working…"
        case .waiting: message = "needs you!"
        case .done: message = "Done!"
        case .failed: message = "something broke"
        }
        let elapsed = s.elapsedText(now: now).map { " · \($0)" } ?? ""
        return (pet.art.name, message + elapsed)
    }

    /// State colour for the bubble glass; `nil` keeps it neutral.
    private var tint: NSColor? {
        switch store.state {
        case .waiting: return NSColor(srgbRed: 1.0, green: 0.55, blue: 0.1, alpha: 0.2)
        case .done: return NSColor(srgbRed: 0.2, green: 0.8, blue: 0.4, alpha: 0.2)
        case .failed: return NSColor(srgbRed: 0.95, green: 0.25, blue: 0.2, alpha: 0.2)
        default: return nil
        }
    }

    private func accessibilityText(_ bubbleText: (title: String, message: String)?) -> String {
        guard let t = bubbleText else { return "Raicode pet, sleeping" }
        return "Raicode pet: \(t.title), \(t.message)"
    }
}

/// A handful of hearts floating up from the pet when it's petted. Reduced motion: one heart, fading only.
struct HeartsBurst: View {
    /// How far above the bottom of the view the hearts start (around the pet's head).
    let originHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Heart: Identifiable {
        let id: Int
        let dx: CGFloat, rise: CGFloat, size: CGFloat, delay: Double
    }

    private let hearts: [Heart] = (0..<6).map { i in
        Heart(id: i, dx: .random(in: -34...34), rise: .random(in: 55...85),
              size: .random(in: 11...17), delay: Double(i) * 0.07)
    }

    var body: some View {
        ZStack {
            ForEach(reduceMotion ? Array(hearts.prefix(1)) : hearts) { heart in
                FloatingHeart(dx: reduceMotion ? 0 : heart.dx, rise: reduceMotion ? 0 : heart.rise,
                              size: heart.size, delay: heart.delay)
            }
        }
        .offset(y: -originHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FloatingHeart: View {
    let dx: CGFloat, rise: CGFloat, size: CGFloat, delay: Double
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.52))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .modifier(HeartFlight(progress: progress, dx: dx, rise: rise))
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).delay(delay)) { progress = 1 }
            }
    }
}

/// Evaluated every frame (animatable), so the heart can fade in, grow, then shrink and fade on the way up.
private struct HeartFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let dx: CGFloat, rise: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let opacity = progress < 0.15 ? progress / 0.15 : (progress > 0.7 ? (1 - progress) / 0.3 : 1)
        content
            .scaleEffect(0.5 + 0.6 * sin(progress * .pi))
            .opacity(Double(opacity))
            .offset(x: dx * progress, y: -rise * progress)
    }
}
