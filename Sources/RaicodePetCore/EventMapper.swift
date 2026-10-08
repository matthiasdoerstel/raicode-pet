import Foundation

/// The subset of a Claude Code hook payload we care about.
public struct HookInput: Decodable, Sendable {
    public var sessionId: String?
    public var cwd: String?
    public var hookEventName: String?
    public var toolName: String?
    public var notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case notificationType = "notification_type"
    }

    public init(sessionId: String?, cwd: String? = nil, hookEventName: String?,
                toolName: String? = nil, notificationType: String? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.toolName = toolName
        self.notificationType = notificationType
    }

    public static func parse(_ data: Data) -> HookInput? {
        try? JSONDecoder().decode(HookInput.self, from: data)
    }
}

public enum HookAction: Equatable, Sendable {
    case set(PetState, detail: String?)
    case delete
    case ignore
}

public enum EventMapper {
    /// Every hook event the app listens to. Used by the installer.
    public static let handledEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "SubagentStart", "PermissionRequest", "Notification", "Stop", "StopFailure",
    ]

    static let waitingNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "agent_needs_input",
    ]

    public static func action(for input: HookInput) -> HookAction {
        guard let event = input.hookEventName else { return .ignore }
        switch event {
        case "SessionStart":
            return .set(.idle, detail: nil)
        case "SessionEnd":
            return .delete
        case "UserPromptSubmit", "SubagentStart":
            return .set(.working, detail: nil)
        case "PreToolUse", "PostToolUse":
            return .set(.working, detail: input.toolName)
        case "PermissionRequest":
            return .set(.waiting, detail: input.toolName)
        case "Notification":
            if let type = input.notificationType, waitingNotifications.contains(type) {
                return .set(.waiting, detail: nil)
            }
            return .ignore
        case "Stop":
            return .set(.done, detail: nil)
        case "StopFailure":
            return .set(.failed, detail: nil)
        default:
            return .ignore
        }
    }

    public enum Outcome: Equatable, Sendable {
        case unchanged
        case remove
        case write(SessionRecord)
    }

    /// Applies a hook to the session's previous record.
    public static func apply(_ input: HookInput, to previous: SessionRecord?, pid: Int32?,
                             now: Date) -> Outcome {
        guard let sessionId = input.sessionId, !sessionId.isEmpty else { return .unchanged }
        switch action(for: input) {
        case .ignore:
            return .unchanged
        case .delete:
            return .remove
        case let .set(state, detail):
            // A SessionStart on resume must not wipe an unacknowledged done/failed.
            if state == .idle, let prev = previous, prev.state.needsAcknowledgement {
                return .unchanged
            }
            let cwd = input.cwd ?? previous?.cwd ?? ""
            let taskStartedAt: Date?
            switch state {
            case .idle: taskStartedAt = nil
            case .done, .failed: taskStartedAt = previous?.taskStartedAt
            default:
                // a new prompt starts a new task; otherwise keep the running task's start
                taskStartedAt = input.hookEventName == "UserPromptSubmit" ? now : (previous?.taskStartedAt ?? now)
            }
            return .write(SessionRecord(
                sessionId: sessionId,
                cwd: cwd,
                project: projectName(for: cwd),
                state: state,
                detail: detail,
                pid: pid ?? previous?.pid,
                updatedAt: now,
                taskStartedAt: taskStartedAt
            ))
        }
    }

    public static func projectName(for cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "raicode" : name
    }
}
