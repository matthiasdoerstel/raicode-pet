import AppKit
import Combine
import RaicodePetCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let store = SessionStore()
    var pets: [PetArt] = []
    var controller: PetController!
    var panel: PetPanel!
    var statusItem: NSStatusItem!
    var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        pets = PetLibrary.available()
        controller = PetController(art: PetLibrary.selected(from: pets))

        buildPanel()
        buildStatusItem()

        store.onTransition = { session, _ in
            if session.state == .waiting || session.state == .done {
                Task { @MainActor in Notifier.announce(session) }
            }
        }
        store.$state
            .sink { [weak self] state in self?.controller.show(state) }
            .store(in: &cancellables)
        store.start()

        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self.map { PetPlacement.clamp($0.panel) } }
        }

        if !HookSetup.isInstalled { offerHookInstall() }
    }

    // MARK: - Panel

    private func buildPanel() {
        let view = PetHostingView(rootView: PetView(pet: controller, store: store))
        view.onClick = { [weak self] event in self?.petClicked(event) }
        view.onRightClick = { [weak self] event in
            guard let self, let view = self.panel.contentView else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: view)
        }
        view.onMoved = { [weak self] in self.map { PetPlacement.save($0.panel) } }
        panel = PetPanel(content: view)
        panel.setContentSize(view.fittingSize)
        PetPlacement.restore(panel)
        panel.orderFrontRegardless()
    }

    private func petClicked(_ event: NSEvent) {
        let active = store.sessions.filter { $0.state != .idle }
        let candidates = active.isEmpty ? store.sessions : active
        if candidates.count <= 1 {
            if let s = candidates.first {
                store.acknowledge(s.sessionId)
                TerminalFocuser.focus(s)
            }
            controller.play(.wave)
            return
        }
        let menu = NSMenu()
        for s in candidates {
            let item = NSMenuItem(title: "\(emoji(s.state))  \(s.project) — \(label(s.state))",
                                  action: #selector(sessionChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.sessionId
            menu.addItem(item)
        }
        if let view = panel.contentView {
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        }
    }

    @objc private func sessionChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let s = store.sessions.first(where: { $0.sessionId == id }) else { return }
        store.acknowledge(id)
        TerminalFocuser.focus(s)
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Raicode Pet")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        store.$state
            .sink { [weak self] state in
                self?.statusItem.button?.contentTintColor = switch state {
                case .waiting: .systemOrange
                case .done: .systemGreen
                case .failed: .systemRed
                default: nil
                }
            }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        makeMenu().items.forEach { item in
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector?, key: String = "", state: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if let state { item.state = state ? .on : .off }
            menu.addItem(item)
        }

        add(panel.isVisible ? "Hide Pet" : "Show Pet", #selector(togglePet), key: "p")
        menu.addItem(.separator())

        if store.sessions.isEmpty {
            let item = NSMenuItem(title: "No Raicode sessions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for s in store.sessions {
                let item = NSMenuItem(title: "\(emoji(s.state))  \(s.project) — \(label(s.state))",
                                      action: #selector(sessionChosen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.sessionId
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let petItem = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        let petMenu = NSMenu()
        for pet in pets {
            let item = NSMenuItem(title: pet.displayName, action: #selector(choosePet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            item.state = pet.id == controller.art.id ? .on : .off
            petMenu.addItem(item)
        }
        petMenu.addItem(.separator())
        let reveal = NSMenuItem(title: "Open Pets Folder…", action: #selector(openPetsFolder), keyEquivalent: "")
        reveal.target = self
        petMenu.addItem(reveal)
        let rescan = NSMenuItem(title: "Reload Pets", action: #selector(reloadPets), keyEquivalent: "")
        rescan.target = self
        petMenu.addItem(rescan)
        petItem.submenu = petMenu
        menu.addItem(petItem)

        add("Notifications", #selector(toggleNotifications), state: Notifier.notificationsEnabled)
        add("Sounds", #selector(toggleSounds), state: Notifier.soundsEnabled)
        add("Launch at Login", #selector(toggleLogin), state: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add(HookSetup.isInstalled ? "Remove Raicode Hooks" : "Install Raicode Hooks", #selector(toggleHooks))
        menu.addItem(.separator())
        add("Quit Raicode Pet", #selector(quit), key: "q")
        return menu
    }

    @objc private func togglePet() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let pet = pets.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: PetLibrary.selectionKey)
        controller.setArt(pet)
        resizePanel()
    }

    @objc private func openPetsFolder() {
        let url = PetLibrary.folders[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func reloadPets() {
        pets = PetLibrary.available()
        controller.setArt(PetLibrary.selected(from: pets))
        resizePanel()
    }

    private func resizePanel() {
        guard let view = panel.contentView else { return }
        let old = panel.frame
        let size = view.fittingSize
        panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height),
                       display: true)
        PetPlacement.clamp(panel)
    }

    @objc private func toggleNotifications() { Notifier.notificationsEnabled.toggle() }
    @objc private func toggleSounds() { Notifier.soundsEnabled.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func toggleHooks() {
        do {
            if HookSetup.isInstalled {
                try HookSetup.remove()
            } else {
                try HookSetup.install()
                alert("Hooks installed", "New Raicode sessions will now talk to your pet. Already-running sessions pick it up after a restart.")
            }
        } catch {
            alert("Couldn't update ~/.claude/settings.json",
                  "The file couldn't be read as JSON, so nothing was changed.\n\n\(error)")
        }
    }

    private func offerHookInstall() {
        let a = NSAlert()
        a.messageText = "Connect Raicode Pet to Raicode?"
        a.informativeText = "This adds hooks to ~/.claude/settings.json (a backup is saved next to it). Your other settings and hooks stay untouched, and you can remove them any time from the menu bar."
        a.addButton(withTitle: "Install Hooks")
        a.addButton(withTitle: "Not Now")
        NSApp.activate()
        if a.runModal() == .alertFirstButtonReturn { toggleHooks() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }

    // MARK: - Notifications

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["sessionId"] as? String else { return }
        await MainActor.run {
            if let s = store.sessions.first(where: { $0.sessionId == id }) {
                store.acknowledge(id)
                TerminalFocuser.focus(s)
            }
        }
    }

    // MARK: - Labels

    private func emoji(_ s: PetState) -> String {
        switch s {
        case .idle: return "💤"
        case .working: return "🏃"
        case .waiting: return "🙋"
        case .done: return "✅"
        case .failed: return "😵"
        }
    }

    private func label(_ s: PetState) -> String {
        switch s {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "needs you"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}
