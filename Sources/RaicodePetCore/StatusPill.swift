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

    /// The dropdown header: how many sessions, and what needs attention. Rows carry each session's own status.
    public static func overview(of sessions: [SessionRecord]) -> String {
        guard !sessions.isEmpty else { return "All quiet" }
        func count(_ state: PetState) -> Int { sessions.filter { $0.state == state }.count }
        var parts = [sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"]
        let waiting = count(.waiting), failed = count(.failed), done = count(.done)
        if waiting > 0 { parts.append(waiting == 1 ? "1 needs you" : "\(waiting) need you") }
        if failed > 0 { parts.append("\(failed) failed") }
        if done > 0 { parts.append("\(done) done") }
        return parts.joined(separator: " · ")
    }
}
