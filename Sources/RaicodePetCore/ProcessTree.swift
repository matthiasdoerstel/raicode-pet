import Darwin
import Foundation

/// Minimal process-table helpers (macOS sysctl).
public enum ProcessTree {
    public struct Info: Equatable, Sendable {
        public let pid: Int32
        public let parent: Int32
        public let name: String
    }

    public static func info(_ pid: Int32) -> Info? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafePointer(to: &kinfo.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
        return Info(pid: pid, parent: kinfo.kp_eproc.e_ppid, name: name)
    }

    /// Ancestors of `pid`, nearest first (excluding `pid` itself, stopping before launchd).
    public static func ancestors(of pid: Int32) -> [Info] {
        var result: [Info] = []
        var current = pid
        for _ in 0..<64 {
            guard let i = info(current), i.parent > 1 else { break }
            guard let p = info(i.parent) else { break }
            result.append(p)
            current = p.pid
        }
        return result
    }

    /// The Claude Code CLI process that spawned this hook, if it can be found.
    public static func claudeProcess(from pid: Int32 = getpid()) -> Int32? {
        ancestors(of: pid).first { $0.name.lowercased().contains("claude") }?.pid
    }

    public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
