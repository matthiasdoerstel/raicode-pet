import Foundation

public enum PetState: String, Codable, CaseIterable, Sendable {
    case idle, working, waiting, done, failed

    /// Higher wins when several sessions are active.
    public var priority: Int {
        switch self {
        case .waiting: return 4
        case .failed: return 3
        case .done: return 2
        case .working: return 1
        case .idle: return 0
        }
    }

    /// States that stay until the user acknowledges them (click or new prompt).
    public var needsAcknowledgement: Bool {
        self == .done || self == .failed
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var project: String
    public var state: PetState
    public var detail: String?
    public var pid: Int32?
    public var updatedAt: Date
    /// When the current task (prompt) began; kept through done/failed so its length is known.
    public var taskStartedAt: Date?
    /// When the session entered its current state; repeat events in the same state keep it.
    public var stateSince: Date?

    public init(sessionId: String, cwd: String, project: String, state: PetState,
                detail: String? = nil, pid: Int32? = nil, updatedAt: Date, taskStartedAt: Date? = nil,
                stateSince: Date? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.project = project
        self.state = state
        self.detail = detail
        self.pid = pid
        self.updatedAt = updatedAt
        self.taskStartedAt = taskStartedAt
        self.stateSince = stateSince
    }

    /// How long the task ran, up to the latest update.
    public var taskDuration: TimeInterval? {
        taskStartedAt.map { updatedAt.timeIntervalSince($0) }
    }

    /// How long the session has been in its current state.
    public func timeInState(now: Date) -> TimeInterval {
        now.timeIntervalSince(stateSince ?? updatedAt)
    }
}

public enum NotificationPolicy {
    /// "Done" only notifies for tasks at least this long; "needs input" always notifies.
    public static let minTaskDuration: TimeInterval = 5 * 60

    public static func shouldAnnounce(_ record: SessionRecord) -> Bool {
        switch record.state {
        case .waiting: return true
        case .done: return (record.taskDuration ?? 0) >= minTaskDuration
        default: return false
        }
    }
}
