import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating the app.
///
/// Both halves matter: `.nonactivatingPanel` keeps the previous app frontmost so
/// focus restore stays cheap, while overriding `canBecomeKey` lets the search field
/// actually receive keystrokes. This is how Spotlight behaves.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Acts on the click that brings the panel forward, rather than swallowing it.
///
/// Without this the panel takes two clicks whenever it is not key: one to take focus and
/// one to do the thing. That is not an edge case here, it is the main flow — arming an
/// item means clicking into another window, which leaves the panel open but inactive, so
/// every return trip costs a wasted click.
///
/// The usual argument against accepting the first mouse is that an activating click can
/// trigger something the user did not mean. That applies to the row's delete button, and
/// it is accepted: the panel is a transient picker whose whole point is being clicked
/// while something else is in front.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// File-scope so the window-move observer can read it without crossing the main
/// actor; it is a constant string, not state.
private let panelOriginKey = "panelOrigin"

@MainActor
final class PanelController {

    private var panel: KeyablePanel?
    private var outsideClickMonitor: Any?
    private var moveObserver: Any?
    private let makeContent: () -> AnyView

    var isVisible: Bool { panel?.isVisible ?? false }
    var onWillShow: (() -> Void)?
    var onHide: (() -> Void)?

    /// What a click in another application means. Normally "dismiss"; while an item is
    /// armed it means "this is the destination", so the owner replaces it.
    var onOutsideClick: (() -> Void)?

    init(content: @escaping () -> AnyView) {
        self.makeContent = content
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        onWillShow?()

        let panel = panel ?? makePanel()
        self.panel = panel

        // Rebuilt every time: the header reports the current target app and profile,
        // and those change between openings.
        panel.contentView = FirstMouseHostingView(rootView: makeContent())

        position(panel)
        panel.makeKeyAndOrderFront(nil)

        // Global monitors only see events delivered to *other* applications, so this
        // fires for clicks outside the panel and never for clicks inside it.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // No default action: the panel stays put unless something is armed. It
            // closes on Esc, the hotkey, or the menu bar item.
            Task { @MainActor in self?.onOutsideClick?() }
        }
    }

    func hide() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
        onHide?()
    }

    private func makePanel() -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // On, but confined: WindowDragBlocker sits under everything except the header,
        // so only the header actually starts a drag.
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Remember where it was dragged to, without waiting for a clean shutdown.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let origin = panel?.frame.origin else { return }
            UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: panelOriginKey)
        }

        return panel
    }

    private var savedOrigin: NSPoint? {
        guard let stored = UserDefaults.standard.dictionary(forKey: panelOriginKey),
              let x = stored["x"] as? Double, let y = stored["y"] as? Double
        else { return nil }
        return NSPoint(x: x, y: y)
    }

    /// Places the panel on the screen the mouse is on. This Mac has three displays —
    /// using the main screen would routinely put the panel somewhere the user is not
    /// looking.
    private func position(_ panel: NSPanel) {
        // Always reuse the last position, on whichever display that was. Following the
        // mouse meant the panel turned up somewhere different depending on where the
        // pointer happened to be; predictable beats convenient here.
        if let saved = savedOrigin, isUsable(origin: saved, size: panel.frame.size) {
            panel.setFrameOrigin(saved)
            return
        }

        // First run, or the display it was last on is no longer attached: bottom right
        // of the screen the mouse is on, clear of the menu bar and Dock.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let margin: CGFloat = 16
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - size.width - margin,
            y: frame.minY + margin
        ))
    }

    /// A remembered position is only good while enough of the panel would still land on
    /// an attached display — otherwise unplugging a monitor strands it off-screen.
    private func isUsable(origin: NSPoint, size: NSSize) -> Bool {
        let proposed = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { screen in
            let overlap = screen.frame.intersection(proposed)
            return overlap.width >= 120 && overlap.height >= 80
        }
    }
}
