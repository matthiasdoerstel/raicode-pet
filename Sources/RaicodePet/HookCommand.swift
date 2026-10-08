import Foundation
import RaicodePetCore

/// `RaicodePet hook` — called by Claude Code for every hook event.
/// Reads the payload from stdin, updates the session file, exits. Never fails loudly.
enum HookCommand {
    static func run() -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = HookInput.parse(data), let sessionId = input.sessionId else { exit(0) }

        let dir = SessionDirectory.default
        let previous = dir.read(sessionId)
        let pid = previous?.pid ?? ProcessTree.claudeProcess()

        switch EventMapper.apply(input, to: previous, pid: pid, now: Date()) {
        case .unchanged:
            break
        case .remove:
            dir.remove(sessionId)
        case let .write(record):
            try? dir.write(record)
        }
        exit(0)
    }
}
