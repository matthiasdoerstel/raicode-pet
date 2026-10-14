import RaicodePetCore
import SwiftUI

struct PetView: View {
    @ObservedObject var pet: PetController
    @ObservedObject var store: SessionStore

    static let bubbleHeight: CGFloat = 64
    static let width: CGFloat = 200

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                Color.clear
                if let text = bubbleText {
                    SpeechBubble(title: text.title, message: text.message, tint: tint)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: Self.bubbleHeight)

            sprite
                .frame(width: pet.art.displaySize.width, height: pet.art.displaySize.height)
        }
        .frame(width: Self.width)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bubbleText?.message)
    }

    @ViewBuilder private var sprite: some View {
        if let frame = pet.frame {
            Image(decorative: frame, scale: 1)
                .resizable()
                .interpolation(pet.art.smoothScaling ? .high : .none)
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var focus: SessionRecord? {
        store.sessions.first { $0.state == store.state }
    }

    private var bubbleText: (title: String, message: String)? {
        guard let s = focus else { return nil }
        let message: String
        switch store.state {
        case .idle: return nil
        case .working: message = s.detail.map { "working… \($0)" } ?? "working…"
        case .waiting: message = "needs you!"
        case .done: message = "Done!"
        case .failed: message = "something broke"
        }
        return (pet.art.name, message)
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

    private var accessibilityText: String {
        guard let t = bubbleText else { return "Raicode pet, sleeping" }
        return "Raicode pet: \(t.title), \(t.message)"
    }
}

struct SpeechBubble: View {
    let title: String
    let message: String
    let tint: Color

    static let tailHeight: CGFloat = 7
    static let cornerRadius: CGFloat = 10

    // Glass tuning (macOS 26+, AppKit window-level glass).
    /// .clear (least frost) or .regular.
    @available(macOS 26.0, *) static var glassStyle: NSGlassEffectView.Style { .clear }
    /// How strongly the glass is tinted toward the state colour.
    static let tintAlpha: Double = 0.3

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                // No tail: window glass only does rounded rects.
                label(titleStyle: .white.opacity(0.9), messageStyle: .white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .background(glass(cornerRadius: Self.cornerRadius))
            } else {
                label(titleStyle: .secondary, messageStyle: tint)
                    .padding(.bottom, Self.tailHeight)
                    .background(
                        BubbleShape()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    )
                    .overlay(BubbleShape().stroke(Color.black.opacity(0.12), lineWidth: 1))
                    .environment(\.colorScheme, .light)
            }
        }
        // Width cap goes outside the bubble, so the bubble hugs short messages.
        .frame(maxWidth: PetView.width - 16)
    }

    @available(macOS 26.0, *)
    private func glass(cornerRadius: CGFloat) -> some View {
        WindowGlass(style: Self.glassStyle, cornerRadius: cornerRadius,
                    tint: NSColor(tint).withAlphaComponent(Self.tintAlpha))
    }

    private func label(titleStyle: some ShapeStyle, messageStyle: some ShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(titleStyle)
            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(messageStyle)
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// AppKit's window-level Liquid Glass, which refracts what's behind the window
/// (unlike SwiftUI's glassEffect, which only has our transparent window to work with).
@available(macOS 26.0, *)
struct WindowGlass: NSViewRepresentable {
    var style: NSGlassEffectView.Style
    var cornerRadius: CGFloat
    var tint: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.style = style
        view.cornerRadius = cornerRadius
        view.tintColor = tint
    }
}

/// Rounded bubble with a tail centred at the bottom, as one shape so glass flows into the tail.
struct BubbleShape: Shape {
    var cornerRadius: CGFloat = 10
    var tailWidth: CGFloat = 12
    var tailHeight: CGFloat = SpeechBubble.tailHeight

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        var tail = Path()
        tail.move(to: CGPoint(x: body.midX - tailWidth / 2, y: body.maxY - 1))
        tail.addLine(to: CGPoint(x: body.midX + tailWidth / 2, y: body.maxY - 1))
        tail.addLine(to: CGPoint(x: body.midX, y: rect.maxY))
        tail.closeSubpath()
        return Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous).union(tail)
    }
}
