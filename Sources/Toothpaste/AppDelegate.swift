import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkey: Hotkey?
    private var panelController: PanelController?
    private var cancellables: Set<AnyCancellable> = []

    private let store = HistoryStore()
    private let engine = TypingEngine()
    private let profiles = ProfileStore()
    private let frontmost = FrontmostWatcher()
    private let panelState = PanelState()
    private let settings = Settings()
    private let accessibility = Accessibility()
    private var onboardingWindow: SettingsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var watcher: ClipboardWatcher?

    private var escapeMonitors: [Any] = []
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any window exists, so nothing is ever drawn in the wrong appearance.
        settings.appearance.apply()
        setUpStatusItem()
        store.maxItems = settings.maxItemsForStore
        setUpClipboardWatching()
        setUpSettingsWindow()
        setUpExpiry()

        // The status line names the active profile, so it has to follow an override
        // changed from the panel's own menu.
        profiles.$manualProfileID
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshStatusLine(force: true) }
            }
            .store(in: &cancellables)

        // The panel stays open while you click around, so the header has to follow.
        frontmost.$app
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshStatusLine() }
            }
            .store(in: &cancellables)
        setUpPanel()
        setUpHotkey()

        // A stale keymap would type the wrong characters after a layout switch.
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engine.invalidateLayouts() }
        }

        setUpOnboarding()

        // Deliberately not calling the system prompt here as well: our own window says
        // more, and two dialogs at once is worse than one good one. macOS shows its
        // prompt at most once per app anyway.
        if !accessibility.isTrusted || Accessibility.debugShowOnboarding { showOnboarding() }

        // A grant that disappears later — a rebuild under a different signature does
        // that — should explain itself rather than leave the app silently inert.
        accessibility.$isTrusted
            .dropFirst()
            .sink { [weak self] trusted in
                Task { @MainActor in
                    guard let self else { return }
                    self.panelState.accessibilityGranted = trusted
                    if !trusted { self.showOnboarding() }
                }
            }
            .store(in: &cancellables)
    }

    private func setUpOnboarding() {
        onboardingWindow = SettingsWindowController(
            title: "Welcome to Toothpaste",
            size: NSSize(width: 460, height: 430)
        ) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                OnboardingView(accessibility: self.accessibility) { [weak self] in
                    self?.onboardingWindow?.close()
                }
            )
        }
    }

    private func showOnboarding() { onboardingWindow?.show() }

    // MARK: - Wiring

    private func setUpClipboardWatching() {
        let watcher = ClipboardWatcher { [weak store] text, concealed in
            store?.add(text: text, concealed: concealed)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func setUpPanel() {
        let controller = PanelController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                PanelView(
                    store: self.store,
                    state: self.panelState,
                    profiles: self.profiles,
                    onArm: { [weak self] item in self?.arm(item) },
                    onOpenSettings: { [weak self] in self?.settingsWindow?.show() },
                    onCopy: { [weak self] item in self?.copyToPasteboard(item) },
                    onDisarm: { [weak self] in self?.disarm() },
                    onClose: { [weak self] in self?.panelController?.hide() }
                )
            )
        }
        controller.onWillShow = { [weak self] in
            guard let self else { return }
            self.panelState.armed = nil
            self.panelState.accessibilityGranted = self.accessibility.isTrusted
            self.refreshStatusLine()
        }
        controller.onHide = { [weak self] in
            self?.panelState.armed = nil
            self?.panelController?.onOutsideClick = nil
        }
        panelController = controller
    }

    /// Expiry runs on a slow timer as well as at launch: an entry that ages past the
    /// limit while the app sits idle should go then, not the next time it happens to
    /// be restarted.
    private func setUpExpiry() {
        applyExpiry()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyExpiry() }
        }
        settings.$retentionHours
            .dropFirst()
            .sink { [weak self] hours in
                Task { @MainActor in self?.store.expire(olderThanHours: hours) }
            }
            .store(in: &cancellables)
    }

    private func applyExpiry() {
        let removed = store.expire(olderThanHours: settings.retentionHours)
        if removed > 0 {
            NSLog("Toothpaste: forgot \(removed) entries past the \(settings.retentionHours)h limit")
        }
    }

    /// Holds a just-happened message on screen briefly, so live tracking does not wipe
    /// "typed 42 characters into X" the instant you click somewhere else.
    private var statusHoldUntil: Date?

    private func refreshStatusLine(force: Bool = false) {
        if !force, let hold = statusHoldUntil, Date() < hold { return }
        statusHoldUntil = nil
        let target = frontmost.app?.localizedName ?? "nothing"
        panelState.statusLine = "\(target)  ·  \(profiles.describeSelection(for: frontmost.app))"
    }

    private func holdStatus(_ line: String, seconds: TimeInterval = 6) {
        panelState.statusLine = line
        statusHoldUntil = Date().addingTimeInterval(seconds)
    }

    private func setUpSettingsWindow() {
        settingsWindow = SettingsWindowController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                SettingsView(
                    settings: self.settings,
                    profiles: self.profiles,
                    store: self.store,
                    accessibility: self.accessibility,
                    onHotkeyChange: { [weak self] combo in self?.changeHotkey(to: combo) ?? nil }
                )
            )
        }
    }

    private func setUpHotkey() {
        hotkey = makeHotkey(settings.hotkey)
        if hotkey == nil {
            NSLog("Toothpaste: could not register \(settings.hotkey.description) at launch")
        }
    }

    private func makeHotkey(_ combo: KeyCombo) -> Hotkey? {
        Hotkey(keyCode: combo.keyCode, modifiers: combo.carbonModifiers) { [weak self] in
            Task { @MainActor in self?.panelController?.toggle() }
        }
    }

    /// Swaps the global shortcut. Returns a message when it could not be taken, so the
    /// settings window can say so instead of leaving a dead shortcut behind.
    private func changeHotkey(to combo: KeyCombo) -> String? {
        // Release the old registration first: Carbon will not hand out a combination
        // that is still held, not even by us.
        hotkey = nil

        if let replacement = makeHotkey(combo) {
            hotkey = replacement
            return nil
        }

        hotkey = makeHotkey(settings.hotkey)
        return "\(combo.description) is already taken by another app"
    }

    // MARK: - Actions

    /// Choosing an item does not deliver it.
    ///
    /// The panel stays open and the next click in another window picks the
    /// destination. Delivering immediately would mean typing into whatever happened
    /// to be frontmost when the panel opened, which is the wrong target as soon as
    /// you want a specific field inside a remote session.
    private func arm(_ item: ClipItem) {
        guard accessibility.isTrusted else {
            // Explaining beats a warning glyph here: the paste the user just asked for
            // is not going to happen, and they need to know what to do about it.
            panelState.accessibilityGranted = false
            showOnboarding()
            return
        }
        panelState.armed = item
        panelController?.onOutsideClick = { [weak self] in self?.deliverArmedItem() }
    }

    /// Cancels a pending choice without closing the panel, so Esc walks back one step
    /// instead of dropping you out entirely.
    private func disarm() {
        panelState.armed = nil
        panelController?.onOutsideClick = nil
        refreshStatusLine(force: true)
    }

    private func deliverArmedItem() {
        guard let item = panelState.armed else {
            panelController?.hide()
            return
        }
        panelState.armed = nil
        panelController?.onOutsideClick = nil
        // Deliberately not hiding: the panel stays on screen so a second item can be
        // sent without reopening it. It loses key focus to the destination, which is
        // exactly what should happen.

        Task { @MainActor in
            guard let destination = await waitForDestination() else {
                flagWarning("No window came forward, so nothing was typed.")
                return
            }
            let profile = profiles.profile(for: destination)
            let name = destination.localizedName ?? "the target"

            holdStatus("typing into \(name)  ·  \(profile.name)  ·  esc cancels", seconds: 3600)
            startEscapeWatch()
            let result = await engine.type(item.text, using: profile)
            stopEscapeWatch()

            if result.cancelled {
                holdStatus("cancelled after \(result.typed) characters into \(name)")
            } else {
                holdStatus("typed \(result.typed) characters into \(name)  ·  \(profile.name)")
            }

            if !result.skipped.isEmpty {
                // Silence here would be dangerous: a password typed short looks like
                // a wrong password, not like a tool that gave up.
                flagIncomplete(skipped: result.skipped, profile: profile)
            }
        }
    }

    /// Esc has to reach us while the *destination* app holds focus, so this needs a
    /// global monitor. It cannot consume the key, so Esc also reaches that app — an
    /// acceptable trade for a cancel that works from anywhere.
    private func startEscapeWatch() {
        stopEscapeWatch()
        let onKey: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in self?.engine.requestCancel() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKey) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            onKey(event)
            return event
        }) {
            escapeMonitors.append(local)
        }
    }

    private func stopEscapeWatch() {
        escapeMonitors.forEach { NSEvent.removeMonitor($0) }
        escapeMonitors.removeAll()
    }

    /// Waits for the window the user just clicked to actually become frontmost.
    /// Typing before that lands the text back in the panel or in the previous app.
    private func waitForDestination(timeout: TimeInterval = 2) async -> NSRunningApplication? {
        let ours = Bundle.main.bundleIdentifier
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != ours {
                return app
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return NSWorkspace.shared.frontmostApplication
    }

    private func copyToPasteboard(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        watcher?.acknowledgeOwnWrite()
    }

    private func flagIncomplete(skipped: [Character], profile: TargetProfile) {
        let unique = String(Array(Set(skipped)).sorted())
        NSLog("Toothpaste: \(skipped.count) character(s) not typeable on \(profile.name): \(unique)")

        flagWarning("Skipped \(skipped.count) character(s) not on the \(profile.name) layout: \(unique)")
    }

    /// Something went wrong in a place the user cannot see, because the panel is
    /// already closed and the target app has focus. The menu bar is the only surface
    /// left.
    private func flagWarning(_ message: String) {
        setStatusGlyph(Self.menuBarWarning)
        statusItem?.button?.toolTip = message

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            self.setStatusGlyph(Self.menuBarIcon)
            self.statusItem?.button?.toolTip = nil
        }
    }

    // MARK: - Status item

    /// Menu bar glyph. Emoji rather than an SF Symbol, by choice — swap the string
    /// and nothing else changes.
    private static let menuBarIcon = "\u{1F4DD}"      // memo
    private static let menuBarWarning = "\u{26A0}\u{FE0F}" // warning

    /// Emoji need a nudge: the system menu bar font renders them small, and they sit
    /// slightly high without a baseline offset.
    private func setStatusGlyph(_ glyph: String) {
        statusItem?.button?.image = nil
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: glyph,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .baselineOffset: -1,
            ]
        )
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        setStatusGlyph(Self.menuBarIcon)
    }

    /// Left-click opens the panel, right-click (or ⌃-click) opens the menu. Assigning
    /// `statusItem.menu` permanently would hand *every* click to the menu, so it is
    /// attached only for the duration of one click.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if wantsMenu {
            statusItem?.menu = buildMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            panelController?.toggle()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Show panel", action: #selector(showPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Typing profile", action: nil, keyEquivalent: ""))

        let auto = NSMenuItem(title: "Automatic", action: #selector(chooseAutomatic), keyEquivalent: "")
        auto.target = self
        auto.state = profiles.manualProfileID == nil ? .on : .off
        auto.indentationLevel = 1
        menu.addItem(auto)

        for profile in profiles.profiles {
            let entry = NSMenuItem(title: profile.name, action: #selector(chooseProfile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.id
            entry.state = profiles.manualProfileID == profile.id ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: LaunchAtLogin.description, action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let trusted = accessibility.isTrusted
        let permission = NSMenuItem(
            title: trusted ? "Accessibility: granted" : "Accessibility: MISSING — click to fix",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        permission.target = self
        permission.state = trusted ? .on : .off
        menu.addItem(permission)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func showPanel() { panelController?.show() }
    @objc private func chooseAutomatic() { profiles.manualProfileID = nil }
    @objc private func openOnboarding() { showOnboarding() }

    @objc private func openSettings() { settingsWindow?.show() }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }

    @objc private func chooseProfile(_ sender: NSMenuItem) {
        profiles.manualProfileID = sender.representedObject as? String
    }
}
