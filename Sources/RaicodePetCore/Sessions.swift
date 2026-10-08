import Foundation

public enum Aggregator {
    /// The single state the pet shows across all sessions.
    public static func state(of sessions: [SessionRecord]) -> PetState {
        sessions.map(\.state).max(by: { $0.priority < $1.priority }) ?? .idle
    }

    /// Sessions sorted most-urgent first, then most recently updated.
    public static func ranked(_ sessions: [SessionRecord]) -> [SessionRecord] {
        sessions.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

public enum Pruner {
    public static let maxAge: TimeInterval = 6 * 60 * 60

    /// Records that belong to sessions which are gone.
    public static func stale(_ sessions: [SessionRecord], now: Date,
                             isAlive: (Int32) -> Bool) -> [SessionRecord] {
        sessions.filter { record in
            if now.timeIntervalSince(record.updatedAt) > maxAge { return true }
            if let pid = record.pid, !isAlive(pid) { return true }
            return false
        }
    }
}

/// Reads and writes session records in a directory, one JSON file per session.
public struct SessionDirectory: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var `default`: SessionDirectory {
        SessionDirectory(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".raicode-pet/sessions", isDirectory: true))
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fileURL(for sessionId: String) -> URL {
        // session ids are UUIDs, but never trust them as path components
        let safe = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return url.appendingPathComponent("\(safe).json")
    }

    public func read(_ sessionId: String) -> SessionRecord? {
        guard let data = try? Data(contentsOf: fileURL(for: sessionId)) else { return nil }
        return try? Self.decoder.decode(SessionRecord.self, from: data)
    }

    public func readAll() -> [SessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? Self.decoder.decode(SessionRecord.self, from: data)
        }
    }

    public func write(_ record: SessionRecord) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Self.encoder.encode(record).write(to: fileURL(for: record.sessionId), options: .atomic)
    }

    public func remove(_ sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
    }
}
