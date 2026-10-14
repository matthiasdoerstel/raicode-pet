import Foundation

/// Names the user gave their pets, one per pet id. Pet files are never touched.
public struct PetNames {
    public static let key = "petNames"
    /// Keeps the speech bubble from overflowing.
    public static let maxLength = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Trimmed and capped; nil when nothing is left.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }

    public func custom(for id: String) -> String? {
        stored[id]
    }

    public func name(for id: String, default fallback: String) -> String {
        custom(for: id) ?? fallback
    }

    /// Saves a name; nil or blank resets the pet to its default name.
    public func set(_ raw: String?, for id: String) {
        var names = stored
        names[id] = raw.flatMap(Self.normalize)
        defaults.set(names, forKey: Self.key)
    }

    private var stored: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
