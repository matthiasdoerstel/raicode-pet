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

    /// The first paragraph of Claude's reply, without Markdown syntax.
    public static func result(_ text: String?) -> String? {
        guard let text else { return nil }
        let prose = text.replacingOccurrences(of: #"```[\s\S]*?(```|$)"#, with: "\n\n", options: .regularExpression)
        let paragraphs = prose.components(separatedBy: "\n\n")
            .map { plain($0) }
            .filter { !$0.isEmpty }
        return paragraphs.first.flatMap { clip($0) }
    }

    /// Strips the Markdown that would show up literally: emphasis, code ticks, headings, list markers, links.
    static func plain(_ paragraph: String) -> String {
        let lines = paragraph.split(whereSeparator: \.isNewline).map { line -> String in
            let l = line.trimmingCharacters(in: .whitespaces)
            return l.replacingOccurrences(of: #"^(#{1,6}|[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        }
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
        return String(s.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
