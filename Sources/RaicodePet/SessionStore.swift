import Foundation
import RaicodePetCore

/// Watches the sessions folder and publishes the current sessions + aggregate state.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var state: PetState = .idle

    /// Called when a session moves into a new state (not on first load).
    var onTransition: ((SessionRecord, PetState?) -> Void)?

    /// A "working" session with no hook activity for this long was most likely
    /// interrupted (Esc doesn't fire Stop) — show it as idle.
    static let workingTimeout: TimeInterval = 15 * 60

    let directory: SessionDirectory
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pendingReload = false
    private var loadedOnce = false

    init(directory: SessionDirectory = .default) {
        self.directory = directory
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        watch()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload(prune: true) }
        }
        reload(prune: true)
    }

    private func watch() {
        let fd = open(directory.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleReload() {
        guard !pendingReload else { return }
        pendingReload = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor in
                self?.pendingReload = false
                self?.reload(prune: false)
            }
        }
    }

    func reload(prune: Bool) {
        let now = Date()
        var records = directory.readAll()
        if prune {
            let stale = Pruner.stale(records, now: now, isAlive: ProcessTree.isAlive)
            stale.forEach { directory.remove($0.sessionId) }
            let staleIds = Set(stale.map(\.sessionId))
            records.removeAll { staleIds.contains($0.sessionId) }
        }
        records = records.map { r in
            var r = r
            if r.state == .working, now.timeIntervalSince(r.updatedAt) > Self.workingTimeout { r.state = .idle }
            return r
        }

        if loadedOnce {
            let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0.state) })
            for r in records where previous[r.sessionId] != r.state {
                onTransition?(r, previous[r.sessionId])
            }
        }
        loadedOnce = true

        sessions = Aggregator.ranked(records)
        state = Aggregator.state(of: records)
    }

    /// Clears done/failed for a session (the user has seen it).
    func acknowledge(_ sessionId: String) {
        guard var r = directory.read(sessionId), r.state.needsAcknowledgement else { return }
        r.state = .idle
        r.detail = nil
        try? directory.write(r)
        reload(prune: false)
    }

    func acknowledgeAll() {
        sessions.filter { $0.state.needsAcknowledgement }.forEach { acknowledge($0.sessionId) }
    }
}
