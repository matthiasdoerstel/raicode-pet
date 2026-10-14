import Foundation

/// What the menu bar shows in quiet mode: a monochrome symbol plus a short, Live Activity–style status.
public enum StatusPill {
    public struct Content: Equatable, Sendable {
        public var symbol: String
        /// Nil when there's nothing worth saying — the item shrinks back to the plain paw.
        public var text: String?

        public init(symbol: String, text: String?) {
            self.symbol = symbol
            self.text = text
        }
    }

    public static func content(for session: SessionRecord?, now: Date) -> Content {
        guard let s = session else { return Content(symbol: "pawprint.fill", text: nil) }
        func with(_ label: String, _ elapsed: String?) -> String {
            elapsed.map { "\(label) · \($0)" } ?? label
        }
        switch s.state {
        case .idle:
            return Content(symbol: "pawprint.fill", text: nil)
        case .working:
            let soFar = s.taskStartedAt.flatMap { DurationText.short(now.timeIntervalSince($0)) }
            return Content(symbol: "arrow.triangle.2.circlepath", text: with("working", soFar))
        case .waiting:
            return Content(symbol: "hand.raised.fill", text: with("needs you", s.elapsedText(now: now)))
        case .done:
            return Content(symbol: "checkmark.circle.fill", text: with("done", s.elapsedText(now: now)))
        case .failed:
            return Content(symbol: "xmark.octagon.fill", text: "failed")
        }
    }
}
