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
