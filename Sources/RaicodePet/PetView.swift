import RaicodePetCore
import SwiftUI

struct PetView: View {
    @ObservedObject var pet: PetController
    @ObservedObject var store: SessionStore

    static let bubbleHeight: CGFloat = 64
    static let width: CGFloat = 240

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
        let extra = store.sessions.filter { $0.state != .idle }.count - 1
        let title = extra > 0 ? "\(s.project) +\(extra)" : s.project
        switch store.state {
        case .idle: return nil
        case .working: return (title, s.detail.map { "working… \($0)" } ?? "working…")
        case .waiting: return (title, "needs you!")
        case .done: return (title, "Done!")
        case .failed: return (title, "something broke")
        }
    }

    private var tint: Color {
        switch store.state {
        case .waiting: return Color(red: 0.93, green: 0.55, blue: 0.12)
        case .done: return Color(red: 0.16, green: 0.6, blue: 0.35)
        case .failed: return Color(red: 0.82, green: 0.22, blue: 0.2)
        default: return Color(white: 0.35)
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            )
            BubbleTail()
                .fill(Color.white)
                .frame(width: 12, height: 7)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
        .frame(maxWidth: PetView.width - 16)
        .environment(\.colorScheme, .light)
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
