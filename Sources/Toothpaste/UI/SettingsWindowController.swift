import AppKit
import SwiftUI

/// Hosts the settings in an ordinary window.
///
/// A separate window rather than something inside the panel: the profile editor needs
/// room, and the panel is deliberately small and transient.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeContent: () -> AnyView
    private let title: String
    private let size: NSSize

    init(
        title: String = "Toothpaste Settings",
        size: NSSize = NSSize(width: 760, height: 660),
        content: @escaping () -> AnyView
    ) {
        self.title = title
        self.size = size
        self.makeContent = content
    }

    func close() { window?.close() }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: makeContent())
            self.window = window
        }

        // An accessory app has to activate deliberately, or the window opens behind
        // whatever the user was in. Since macOS 14 that is a request the system may turn
        // down, and it does when nobody clicked anything — the app started on its own, as
        // after an update, which is exactly when the failure report opens. So the window
        // is also ordered to the front regardless, which works while the app is inactive
        // and does not take the keyboard from whatever the user is typing in.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
