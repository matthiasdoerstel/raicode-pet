import Foundation
@testable import RaicodePetCore
import XCTest

final class EventMapperTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func input(_ event: String, tool: String? = nil, notification: String? = nil) -> HookInput {
        HookInput(sessionId: "s1", cwd: "/Users/m/Projects/eufemia", hookEventName: event,
                  toolName: tool, notificationType: notification)
    }

    func testEventToStateMapping() {
        XCTAssertEqual(EventMapper.action(for: input("SessionStart")), .set(.idle, detail: nil))
        XCTAssertEqual(EventMapper.action(for: input("UserPromptSubmit")), .set(.working, detail: nil))
        XCTAssertEqual(EventMapper.action(for: input("PreToolUse", tool: "Bash")), .set(.working, detail: "Bash"))
        XCTAssertEqual(EventMapper.action(for: input("PermissionRequest", tool: "Bash")), .set(.waiting, detail: "Bash"))
        XCTAssertEqual(EventMapper.action(for: input("Notification", notification: "permission_prompt")), .set(.waiting, detail: nil))
        XCTAssertEqual(EventMapper.action(for: input("Notification", notification: "idle_prompt")), .ignore)
        XCTAssertEqual(EventMapper.action(for: input("Stop")), .set(.done, detail: nil))
        XCTAssertEqual(EventMapper.action(for: input("StopFailure")), .set(.failed, detail: nil))
        XCTAssertEqual(EventMapper.action(for: input("PostToolUseFailure")), .ignore)
        XCTAssertEqual(EventMapper.action(for: input("SessionEnd")), .delete)
        XCTAssertEqual(EventMapper.action(for: input("SomethingNew")), .ignore)
    }

    func testApplyWritesRecordWithProjectName() {
        guard case let .write(r) = EventMapper.apply(input("UserPromptSubmit"), to: nil, pid: 42, now: now) else {
            return XCTFail("expected write")
        }
        XCTAssertEqual(r.project, "eufemia")
        XCTAssertEqual(r.state, .working)
        XCTAssertEqual(r.pid, 42)
    }

    func testTaskStartIsKeptThroughWorkAndDone() {
        guard case let .write(started) = EventMapper.apply(input("UserPromptSubmit"), to: nil, pid: 1, now: now),
              case let .write(working) = EventMapper.apply(input("PreToolUse"), to: started, pid: 1,
                                                           now: now.addingTimeInterval(60)),
              case let .write(done) = EventMapper.apply(input("Stop"), to: working, pid: 1,
                                                        now: now.addingTimeInterval(400)) else {
            return XCTFail("expected writes")
        }
        XCTAssertEqual(started.taskStartedAt, now)
        XCTAssertEqual(working.taskStartedAt, now)
        XCTAssertEqual(done.taskDuration, 400)
    }

    func testNotificationPolicy() {
        func record(_ state: PetState, ran seconds: TimeInterval?) -> SessionRecord {
            SessionRecord(sessionId: "s", cwd: "/x", project: "x", state: state, updatedAt: now,
                          taskStartedAt: seconds.map { now.addingTimeInterval(-$0) })
        }
        XCTAssertFalse(NotificationPolicy.shouldAnnounce(record(.done, ran: 30)))
        XCTAssertFalse(NotificationPolicy.shouldAnnounce(record(.done, ran: nil)))
        XCTAssertTrue(NotificationPolicy.shouldAnnounce(record(.done, ran: 5 * 60)))
        XCTAssertTrue(NotificationPolicy.shouldAnnounce(record(.waiting, ran: 5)))
        XCTAssertFalse(NotificationPolicy.shouldAnnounce(record(.working, ran: 600)))
    }

    func testSessionStartDoesNotClearUnacknowledgedDone() {
        let done = SessionRecord(sessionId: "s1", cwd: "/x", project: "x", state: .done, updatedAt: now)
        XCTAssertEqual(EventMapper.apply(input("SessionStart"), to: done, pid: nil, now: now), .unchanged)
    }

    func testMissingSessionIdIsNoOp() {
        let i = HookInput(sessionId: nil, hookEventName: "Stop")
        XCTAssertEqual(EventMapper.apply(i, to: nil, pid: nil, now: now), .unchanged)
    }

    func testParseRealPayload() {
        let json = #"{"session_id":"abc","cwd":"/a/b","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}"#
        let i = HookInput.parse(Data(json.utf8))
        XCTAssertEqual(i?.sessionId, "abc")
        XCTAssertEqual(i?.toolName, "Bash")
        XCTAssertNil(HookInput.parse(Data("not json".utf8)))
    }
}

final class AggregatorTests: XCTestCase {
    func rec(_ id: String, _ s: PetState, _ t: TimeInterval = 0) -> SessionRecord {
        SessionRecord(sessionId: id, cwd: "/", project: id, state: s, updatedAt: Date(timeIntervalSince1970: t))
    }

    func testPriority() {
        XCTAssertEqual(Aggregator.state(of: []), .idle)
        XCTAssertEqual(Aggregator.state(of: [rec("a", .working), rec("b", .done)]), .done)
        XCTAssertEqual(Aggregator.state(of: [rec("a", .failed), rec("b", .waiting)]), .waiting)
        XCTAssertEqual(Aggregator.state(of: [rec("a", .idle), rec("b", .working)]), .working)
    }

    func testRanking() {
        let r = Aggregator.ranked([rec("a", .working, 5), rec("b", .waiting, 1), rec("c", .working, 9)])
        XCTAssertEqual(r.map(\.sessionId), ["b", "c", "a"])
    }

    func testPruner() {
        let now = Date(timeIntervalSince1970: 100_000)
        var old = rec("old", .idle, 0)
        old.pid = nil
        var dead = rec("dead", .working, 99_990)
        dead.pid = 111
        var alive = rec("alive", .working, 99_990)
        alive.pid = 222
        let stale = Pruner.stale([old, dead, alive], now: now, isAlive: { $0 == 222 })
        XCTAssertEqual(Set(stale.map(\.sessionId)), ["old", "dead"])
    }
}

final class SessionDirectoryTests: XCTestCase {
    func testRoundTripAndRemove() throws {
        let dir = SessionDirectory(url: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let r = SessionRecord(sessionId: "abc-1", cwd: "/a", project: "a", state: .done,
                              detail: "Bash", pid: 5, updatedAt: Date(timeIntervalSince1970: 1000))
        try dir.write(r)
        XCTAssertEqual(dir.read("abc-1"), r)
        XCTAssertEqual(dir.readAll(), [r])
        dir.remove("abc-1")
        XCTAssertEqual(dir.readAll(), [])
    }

    func testHostileSessionIdStaysInDirectory() {
        let dir = SessionDirectory(url: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(dir.fileURL(for: "../../etc/passwd").deletingLastPathComponent().path, "/tmp/x")
    }
}

final class HookInstallerTests: XCTestCase {
    let exe = "/Applications/RaicodePet.app/Contents/MacOS/RaicodePet"

    func json(_ d: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: d) as! [String: Any]
    }

    func testInstallIntoEmpty() throws {
        let out = json(try HookInstaller.install(into: nil, executablePath: exe))
        let hooks = out["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), Set(EventMapper.handledEvents))
        XCTAssertTrue(HookInstaller.isInstalled(in: try HookInstaller.install(into: nil, executablePath: exe)))
    }

    func testPreservesExistingSettingsAndHooks() throws {
        let existing = #"""
        {"model":"opus","statusLine":{"type":"command","command":"x"},
         "hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
        """#
        let installed = try HookInstaller.install(into: Data(existing.utf8), executablePath: exe)
        let out = json(installed)
        XCTAssertEqual(out["model"] as? String, "opus")
        XCTAssertNotNil(out["statusLine"])
        let stop = (out["hooks"] as! [String: Any])["Stop"] as! [Any]
        XCTAssertEqual(stop.count, 2)

        let removed = json(try HookInstaller.remove(from: installed))
        let stopAfter = (removed["hooks"] as! [String: Any])["Stop"] as! [Any]
        XCTAssertEqual(stopAfter.count, 1)
        XCTAssertEqual((removed["hooks"] as! [String: Any]).keys.sorted(), ["Stop"])
        XCTAssertEqual(removed["model"] as? String, "opus")
    }

    func testInstallIsIdempotent() throws {
        let once = try HookInstaller.install(into: nil, executablePath: exe)
        let twice = try HookInstaller.install(into: once, executablePath: exe)
        let stop = (json(twice)["hooks"] as! [String: Any])["Stop"] as! [Any]
        XCTAssertEqual(stop.count, 1)
    }

    func testRemoveFromCleanInstallLeavesNoHooksKey() throws {
        let once = try HookInstaller.install(into: Data("{\"a\":1}".utf8), executablePath: exe)
        let out = json(try HookInstaller.remove(from: once))
        XCTAssertNil(out["hooks"])
        XCTAssertEqual(out["a"] as? Int, 1)
    }

    func testRefusesMalformedSettings() {
        XCTAssertThrowsError(try HookInstaller.install(into: Data("{oops".utf8), executablePath: exe))
    }
}

final class LookDirectionTests: XCTestCase {
    func testCardinalAndDiagonalDirections() {
        XCTAssertEqual(LookDirection.index(dx: 0, dy: 10), 0)    // up
        XCTAssertEqual(LookDirection.index(dx: 10, dy: 10), 2)   // up-right, 45°
        XCTAssertEqual(LookDirection.index(dx: 10, dy: 0), 4)    // right
        XCTAssertEqual(LookDirection.index(dx: 0, dy: -10), 8)   // down
        XCTAssertEqual(LookDirection.index(dx: -10, dy: 0), 12)  // left
    }

    func testWrapsAroundNearUp() {
        XCTAssertEqual(LookDirection.index(dx: -0.1, dy: 10), 0)
        XCTAssertEqual(LookDirection.index(dx: -10, dy: 9.5), 14)
    }
}

final class PetNamesTests: XCTestCase {
    var defaults: UserDefaults!
    var names: PetNames!

    override func setUp() {
        defaults = UserDefaults(suiteName: "PetNamesTests")!
        defaults.removePersistentDomain(forName: "PetNamesTests")
        names = PetNames(defaults: defaults)
    }

    func testNormalizeTrimsAndCaps() {
        XCTAssertEqual(PetNames.normalize("  Rex \n"), "Rex")
        XCTAssertNil(PetNames.normalize("   "))
        XCTAssertEqual(PetNames.normalize(String(repeating: "a", count: 30))?.count, PetNames.maxLength)
    }

    func testFallsBackToDefaultName() {
        XCTAssertEqual(names.name(for: "pixel-golden", default: "Sunny"), "Sunny")
    }

    func testEachPetKeepsItsOwnName() {
        names.set("Rex", for: "pixel-golden")
        names.set("Nugget", for: "hamjji")
        XCTAssertEqual(names.name(for: "pixel-golden", default: "Sunny"), "Rex")
        XCTAssertEqual(names.name(for: "hamjji", default: "Goldie"), "Nugget")
        XCTAssertEqual(names.name(for: "pixel-cat", default: "Mochi"), "Mochi")
    }

    func testEmptyOrNilResetsToDefault() {
        names.set("Rex", for: "pixel-golden")
        names.set("  ", for: "pixel-golden")
        XCTAssertNil(names.custom(for: "pixel-golden"))
        names.set("Rex", for: "pixel-golden")
        names.set(nil, for: "pixel-golden")
        XCTAssertEqual(names.name(for: "pixel-golden", default: "Sunny"), "Sunny")
    }
}

final class StateSinceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func input(_ event: String, notification: String? = nil) -> HookInput {
        HookInput(sessionId: "s1", cwd: "/tmp/p", hookEventName: event, toolName: "Bash",
                  notificationType: notification)
    }

    func record(_ outcome: EventMapper.Outcome) -> SessionRecord? {
        if case let .write(r) = outcome { return r }
        return nil
    }

    func testStateSinceStartsWhenStateChanges() {
        let working = record(EventMapper.apply(input("UserPromptSubmit"), to: nil, pid: 1, now: t0))
        XCTAssertEqual(working?.stateSince, t0)
        let waiting = record(EventMapper.apply(input("PermissionRequest"), to: working, pid: 1,
                                               now: t0.addingTimeInterval(30)))
        XCTAssertEqual(waiting?.stateSince, t0.addingTimeInterval(30))
    }

    func testRepeatEventsInSameStateKeepTheClock() {
        let waiting = record(EventMapper.apply(input("PermissionRequest"), to: nil, pid: 1, now: t0))
        let again = record(EventMapper.apply(input("Notification", notification: "permission_prompt"),
                                             to: waiting, pid: 1, now: t0.addingTimeInterval(90)))
        XCTAssertEqual(again?.stateSince, t0)
        XCTAssertEqual(again?.updatedAt, t0.addingTimeInterval(90))
    }

    func testOldRecordsWithoutStateSinceStillDecode() throws {
        let json = #"{"sessionId":"s1","cwd":"/tmp","project":"tmp","state":"waiting","updatedAt":0}"#
        let r = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertNil(r.stateSince)
    }
}

final class DurationTextTests: XCTestCase {
    func testShortDurations() {
        XCTAssertNil(DurationText.short(0))
        XCTAssertNil(DurationText.short(59))
        XCTAssertEqual(DurationText.short(60), "1 min")
        XCTAssertEqual(DurationText.short(4 * 60 + 50), "4 min")
        XCTAssertEqual(DurationText.short(65 * 60), "1 h 5 min")
        XCTAssertEqual(DurationText.short(120 * 60), "2 h")
    }
}

final class ElapsedTextTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testWaitingCountsFromStateSinceAndDoneShowsTaskLength() {
        var r = SessionRecord(sessionId: "s", cwd: "/p", project: "p", state: .waiting,
                              updatedAt: t0, taskStartedAt: t0.addingTimeInterval(-600), stateSince: t0)
        XCTAssertEqual(r.elapsedText(now: t0.addingTimeInterval(4 * 60)), "4 min")
        r.state = .done
        XCTAssertEqual(r.elapsedText(now: t0.addingTimeInterval(3600)), "10 min")
        r.state = .working
        XCTAssertNil(r.elapsedText(now: t0.addingTimeInterval(3600)))
    }
}
