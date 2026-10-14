import Foundation

/// Turns hook text into short, plain lines for the dropdown's task summary.
public enum TaskText {
    static let maxLength = 160

    /// The user's prompt as one line.
    public static func prompt(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.flatMap { clip(collapse($0)) }
    }

    /// The opening of Claude's reply, without Markdown syntax. Reads on past the first paragraph,
    /// so a lead-in like "Both changes are in:" keeps the list that follows.
    public static func result(_ text: String?) -> String? {
        guard let text else { return nil }
        let prose = text.replacingOccurrences(of: #"```[\s\S]*?(```|$)"#, with: "\n\n", options: .regularExpression)
        let paragraphs = prose.components(separatedBy: "\n\n")
            .map { plain($0) }
            .filter { !$0.isEmpty }
        return clip(paragraphs.joined(separator: " "))
    }

    /// Strips the Markdown that would show up literally: emphasis, code ticks, list markers, links; drops headings.
    static func plain(_ paragraph: String) -> String {
        let lines = paragraph.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") }  // headings are labels, not content
            .map { $0.replacingOccurrences(of: #"^([-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression) }
        var s = lines.joined(separator: " ")
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        return collapse(s)
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func clip(_ s: String) -> String? {
        guard !s.isEmpty else { return nil }
        guard s.count > maxLength else { return s }
        var cut = String(s.prefix(maxLength - 1))
        if let space = cut.lastIndex(of: " ") { cut = String(cut[..<space]) }  // whole words only
        return cut.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}
