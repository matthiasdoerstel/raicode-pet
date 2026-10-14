import RaicodePetCore
import SwiftUI

struct PetView: View {
    @ObservedObject var pet: PetController
    @ObservedObject var store: SessionStore

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
            ZStack(alignment: .bottom) {
                Color.clear
                if let text = bubbleText {
                    SpeechBubble(title: text.title, message: text.message, tint: tint)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: Self.bubbleHeight)

            sprite(label: accessibilityText(bubbleText))
                .frame(width: pet.art.displaySize.width, height: pet.art.displaySize.height)
        }
        .frame(width: Self.width)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bubbleText?.message)
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

    /// Deep enough to carry white text (≥ 4.5:1) as a glass tint, and dark text-on-white as a fallback.
    private var tint: Color {
        switch store.state {
        case .waiting: return Color(red: 0.71, green: 0.33, blue: 0.04)
        case .done: return Color(red: 0.12, green: 0.48, blue: 0.27)
        case .failed: return Color(red: 0.71, green: 0.14, blue: 0.09)
        default: return Color(white: 0.24)
        }
    }

    private func accessibilityText(_ bubbleText: (title: String, message: String)?) -> String {
        guard let t = bubbleText else { return "Raicode pet, sleeping" }
        return "Raicode pet: \(t.title), \(t.message)"
    }
}

struct SpeechBubble: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        // Built like the menu bar dropdown: an NSGlassEffectView that *contains* the text.
        // (SwiftUI's .glassEffect rendered as a flat frosted fill here, losing the tint and the rim.)
        GlassContainer(cornerRadius: 12, tint: NSColor(tint)) { label }
            .fixedSize()
            // Width cap goes outside the bubble, so the bubble hugs short messages.
            .frame(maxWidth: PetView.width - 16)
    }

    private var label: some View {
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
    }
}

/// Hosts SwiftUI content *inside* an NSGlassEffectView, the way AppKit expects glass to be used.
struct GlassContainer<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: NSColor?
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.contentView = NSHostingView(rootView: content)
        updateNSView(glass, context: context)
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSGlassEffectView, context: Context) -> CGSize? {
        (nsView.contentView as? NSHostingView<Content>)?.fittingSize
    }
}
