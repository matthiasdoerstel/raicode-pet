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

    public init(sessionId: String, cwd: String, project: String, state: PetState,
                detail: String? = nil, pid: Int32? = nil, updatedAt: Date) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.project = project
        self.state = state
        self.detail = detail
        self.pid = pid
        self.updatedAt = updatedAt
    }
}
