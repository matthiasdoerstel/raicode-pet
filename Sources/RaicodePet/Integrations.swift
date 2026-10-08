import AppKit
import RaicodePetCore
import UserNotifications

enum TerminalFocuser {
    static let knownTerminals = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal",
                                 "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                                 "dev.zed.Zed"]

    /// Brings the GUI app that hosts this Claude Code process to the front.
    static func focus(_ session: SessionRecord) {
        if let pid = session.pid, let app = hostApp(of: pid) {
            activate(app)
            return
        }
        // Couldn't resolve (e.g. tmux) — fall back to the first running terminal.
        for id in knownTerminals {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                activate(app)
                return
            }
        }
    }

    static func hostApp(of pid: Int32) -> NSRunningApplication? {
        for ancestor in ProcessTree.ancestors(of: pid) {
            if let app = NSRunningApplication(processIdentifier: ancestor.pid),
               app.activationPolicy == .regular {
                return app
            }
        }
        return nil
    }

    private static func activate(_ app: NSRunningApplication) {
        // openApplication reliably brings an already-running app forward, even from a
        // non-activating panel where NSRunningApplication.activate is ignored.
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        } else {
            app.activate()
        }
    }
}

@MainActor
enum Notifier {
    static let notificationsKey = "notificationsEnabled"
    static let soundsKey = "soundsEnabled"

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notificationsKey) }
    }

    static var soundsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundsKey) }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func announce(_ session: SessionRecord) {
        let message: String
        let sound: String
        switch session.state {
        case .waiting: message = "🙋 Needs your input"; sound = "Glass"
        case .done: message = "✅ Done!"; sound = "Hero"
        default: return
        }
        if soundsEnabled { NSSound(named: sound)?.play() }
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = message
        content.subtitle = session.project
        if let d = session.detail { content.body = d }
        content.userInfo = ["sessionId": session.sessionId]
        let request = UNNotificationRequest(identifier: "\(session.sessionId)-\(session.state.rawValue)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Reads/writes ~/.claude/settings.json around HookInstaller, with a backup.
enum HookSetup {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var isInstalled: Bool {
        HookInstaller.isInstalled(in: try? Data(contentsOf: settingsURL))
    }

    static func install() throws {
        guard let exe = Bundle.main.executablePath else { return }
        try update { try HookInstaller.install(into: $0, executablePath: exe) }
    }

    static func remove() throws {
        try update { try HookInstaller.remove(from: $0) }
    }

    private static func update(_ transform: (Data?) throws -> Data) throws {
        let fm = FileManager.default
        let current = try? Data(contentsOf: settingsURL)
        let updated = try transform(current)
        if let current {
            try current.write(to: settingsURL.appendingPathExtension("raicode-pet.bak"), options: .atomic)
        } else {
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try updated.write(to: settingsURL, options: .atomic)
    }
}
