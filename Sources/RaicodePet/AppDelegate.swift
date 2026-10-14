import AppKit
import Combine
import RaicodePetCore
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject,
                         UNUserNotificationCenterDelegate {
    let store = SessionStore()
    // Created up front: the MenuBarExtra scene reads these before launch finishes.
    @Published private(set) var pets: [PetArt]
    let controller: PetController
    var panel: PetPanel!
    private var bubble: BubbleWindow?
    private var bubbleSpec: BubbleSpec?
    private var strokes = StrokeDetector()
    var statusItem: NSStatusItem!
    var cancellables: Set<AnyCancellable> = []
    private var clock: Timer?
    /// Sits over the button's icon so the symbol can animate; NSStatusBarButton can't animate symbols itself.
    private let symbolView = NSImageView()
    private var animatedState: PetState?
    private let classicMenu = NSMenu()
    private let dropdown = GlassDropdown()

    /// Quiet mode hides the pet and shows a compact status in the menu bar instead.
    private static let quietKey = "quietMode"
    @Published private(set) var quietMode = UserDefaults.standard.bool(forKey: AppDelegate.quietKey) {
        didSet { UserDefaults.standard.set(quietMode, forKey: Self.quietKey) }
    }
    /// Ticks every 30 s so timers in the menu bar and panel keep counting.
    @Published private(set) var now = Date()

    override init() {
        let pets = PetLibrary.available()
        self.pets = pets
        controller = PetController(art: PetLibrary.selected(from: pets))
        super.init()
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var hooksInstalled: Bool { HookSetup.isInstalled }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.updateStatusItem()
            }
        }

        store.onTransition = { session, _ in
            if NotificationPolicy.shouldAnnounce(session) {
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
        let view = PetHostingView(rootView: PetView(pet: controller, store: store) { [weak self] spec in
            self?.bubbleSpec = spec
            self?.bubble?.update(spec)
        })
        view.onClick = { [weak self] event in self?.petClicked(event) }
        view.onRightClick = { [weak self] event in
            guard let self, let view = self.panel.contentView else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: view)
        }
        view.onDrag = { [weak self] dx in self?.controller.dragged(dx: dx) }
        view.onHover = { [weak self, weak view] point in
            guard let self, let view else { return }
            self.pointerMoved(to: point, in: view)
        }
        view.onHoverEnded = { [weak self] in self?.strokes.reset() }
        view.onMoved = { [weak self] in
            guard let self else { return }
            self.controller.dragEnded()
            PetPlacement.save(self.panel)
        }
        panel = PetPanel(content: view)
        panel.setContentSize(view.fittingSize)
        PetPlacement.restore(panel)
        controller.window = panel
        bubble = BubbleWindow(parent: panel, eventTarget: view)
        if !quietMode { panel.orderFrontRegardless() }
        bubble?.update(bubbleSpec)
    }

    /// Strokes over the sprite (not the empty bubble strip above it) count towards petting.
    private func pointerMoved(to point: NSPoint, in view: NSView) {
        let size = controller.art.displaySize
        let spriteTop = view.isFlipped ? view.bounds.height - size.height : size.height
        let overSprite = abs(point.x - view.bounds.midX) <= size.width / 2
            && (view.isFlipped ? point.y >= spriteTop : point.y <= spriteTop)
        guard overSprite else { return strokes.reset() }
        if strokes.add(x: point.x, at: Date()) { controller.pet() }
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
            let item = NSMenuItem(title: menuTitle(s),
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
        select(s)
    }

    /// Jumps to a session's terminal and acknowledges it.
    func select(_ s: SessionRecord) {
        dropdown.close()
        store.acknowledge(s.sessionId)
        TerminalFocuser.focus(s)
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        classicMenu.delegate = self
        // Left-click opens the glass dropdown, right-click the classic menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()

        // @Published fires before the value lands; hop to the next run loop turn to read it.
        store.$sessions.combineLatest(store.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    /// Template images and plain text, so macOS draws it black or white to suit the menu bar and wallpaper.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let focus = store.sessions.first { $0.state == store.state }
        let content = quietMode
            ? StatusPill.content(for: focus, now: Date())
            : StatusPill.Content(symbol: "pawprint.fill", text: nil)

        let icon = NSImage(systemSymbolName: content.symbol, accessibilityDescription: content.text ?? "Raicode Pet")
        icon?.isTemplate = true
        button.image = icon
        let animate = quietMode && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let text = content.text {
            statusItem.length = NSStatusItem.variableLength
            button.title = " " + text
            button.imagePosition = .imageLeading
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        }
        updateSymbolEffect(animate ? store.state : nil, icon: icon, in: button)
    }

    /// Animates the menu bar symbol per state: working spins, needs-you wiggles now and then,
    /// done bounces once. Other states (or nil) show the plain button image.
    private func updateSymbolEffect(_ state: PetState?, icon: NSImage?, in button: NSStatusBarButton) {
        guard #available(macOS 15.0, *), let icon, let state, [.working, .waiting, .done].contains(state) else {
            symbolView.removeFromSuperview()
            symbolView.removeAllSymbolEffects()
            animatedState = nil
            return
        }
        // A blank placeholder keeps the button's layout; the overlay draws the real symbol on top.
        let placeholder = NSImage(size: icon.size)
        placeholder.isTemplate = true
        button.image = placeholder
        if symbolView.superview !== button {
            symbolView.imageScaling = .scaleNone
            button.addSubview(symbolView)
        }
        if animatedState != state {
            animatedState = state
            symbolView.image = icon
            symbolView.removeAllSymbolEffects()
            switch state {
            case .working: symbolView.addSymbolEffect(.rotate, options: .repeat(.continuous))
            case .waiting: symbolView.addSymbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)))
            default: symbolView.addSymbolEffect(.bounce, options: .nonRepeating)
            }
        }
        // Position once the variable-length item has resized.
        DispatchQueue.main.async { [symbolView] in
            guard let cell = button.cell else { return }
            symbolView.frame = cell.imageRect(forBounds: button.bounds)
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            dropdown.close()
            showClassicMenu()
        } else if dropdown.isShown {
            dropdown.close()
        } else if let button = statusItem.button {
            dropdown.show(StatusPanel(app: self, pet: controller, store: store), below: button)
        }
    }

    private func showClassicMenu() {
        // Attach the menu just for this click, so left-clicks keep opening the dropdown.
        statusItem.menu = classicMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        makeMenu().items.forEach { item in
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    // MARK: - Pet context menu

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
                let item = NSMenuItem(title: menuTitle(s),
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
            let item = NSMenuItem(title: pet.menuTitle, action: #selector(choosePet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.id
            item.state = pet.id == controller.art.id ? .on : .off
            petMenu.addItem(item)
        }
        petMenu.addItem(.separator())
        let rename = NSMenuItem(title: "Rename “\(controller.art.name)”…", action: #selector(renamePet),
                                keyEquivalent: "")
        rename.target = self
        petMenu.addItem(rename)
        petMenu.addItem(.separator())
        let reveal = NSMenuItem(title: "Open Pets Folder…", action: #selector(openPetsFolder), keyEquivalent: "")
        reveal.target = self
        petMenu.addItem(reveal)
        let rescan = NSMenuItem(title: "Reload Pets", action: #selector(reloadPets), keyEquivalent: "")
        rescan.target = self
        petMenu.addItem(rescan)
        petItem.submenu = petMenu
        menu.addItem(petItem)

        add("Quiet Mode", #selector(toggleQuietMode), key: "d", state: quietMode)
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
        if quietMode { return toggleQuietMode() }  // showing the pet ends quiet mode
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        bubble?.syncVisibility()
    }

    @objc func toggleQuietMode() {
        quietMode.toggle()
        if quietMode { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        bubble?.syncVisibility()
        updateStatusItem()
    }

    @objc private func choosePet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        choosePet(id: id)
    }

    func choosePet(id: String) {
        guard let pet = pets.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: PetLibrary.selectionKey)
        controller.setArt(pet)
        resizePanel()
    }

    @objc func renamePet() {
        let art = controller.art
        let names = PetNames()

        let alert = NSAlert()
        alert.messageText = "Rename \(art.name)"
        alert.informativeText = "Each pet keeps its own name. Default: \(art.displayName)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if names.custom(for: art.id) != nil { alert.addButton(withTitle: "Reset to Default") }

        let field = NSTextField(string: art.name)
        field.placeholderString = art.displayName
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        // The app has no Dock icon; bring it forward so the field can take typing.
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: names.set(field.stringValue, for: art.id)
        case .alertThirdButtonReturn: names.set(nil, for: art.id)
        default: return
        }
        controller.setArt(art)  // republishes, so the bubble picks up the new name
        objectWillChange.send()  // and the panel's pet list
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

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription)
        }
        objectWillChange.send()
    }

    @objc func toggleHooks() {
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
        objectWillChange.send()
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

    @objc func quit() { NSApp.terminate(nil) }

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

    private func menuTitle(_ s: SessionRecord) -> String {
        let elapsed = s.elapsedText(now: Date()).map { " · \($0)" } ?? ""
        return "\(emoji(s.state))  \(s.project) — \(label(s.state))\(elapsed)"
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
