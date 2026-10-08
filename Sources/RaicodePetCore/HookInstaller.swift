import Foundation

/// Adds and removes this app's hook entries in Claude Code's settings.json,
/// leaving everything else untouched.
public enum HookInstaller {
    public enum Failure: Error, Equatable {
        case unreadableSettings
    }

    /// Our entries are recognised by this marker in the command string.
    public static let marker = "RaicodePet hook"

    public static func command(forExecutable path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))' hook"
    }

    public static func isOurs(_ command: String) -> Bool {
        command.contains("RaicodePet' hook") || command.contains(marker)
    }

    /// Returns new settings JSON with our hooks installed (replacing any previous install).
    public static func install(into settings: Data?, executablePath: String) throws -> Data {
        var root = try parse(settings)
        root = strip(root)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let entry: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": command(forExecutable: executablePath),
                "timeout": 5,
            ]],
        ]
        for event in EventMapper.handledEvents {
            var groups = hooks[event] as? [Any] ?? []
            groups.append(entry)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    /// Returns new settings JSON with only our hooks removed.
    public static func remove(from settings: Data?) throws -> Data {
        try serialize(strip(try parse(settings)))
    }

    public static func isInstalled(in settings: Data?) -> Bool {
        guard let root = try? parse(settings), let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return hooks.values.contains { groups in
            (groups as? [Any] ?? []).contains { containsOurs($0) }
        }
    }

    // MARK: - helpers

    static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 })
        else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings
        }
        return obj
    }

    static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    static func containsOurs(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let list = g["hooks"] as? [Any] else { return false }
        return list.contains { ((($0 as? [String: Any])?["command"]) as? String).map(isOurs) ?? false }
    }

    static func strip(_ root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            var kept: [Any] = []
            for group in groups {
                guard var g = group as? [String: Any], let list = g["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let remaining = list.filter {
                    !(((($0 as? [String: Any])?["command"]) as? String).map(isOurs) ?? false)
                }
                if remaining.isEmpty { continue }
                g["hooks"] = remaining
                kept.append(g)
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }
}
