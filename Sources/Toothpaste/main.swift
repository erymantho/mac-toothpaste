import AppKit

// Top-level code is not main-actor isolated, but it does run on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared

    // Held for the lifetime of run() — NSApplication does not retain its delegate.
    let delegate = AppDelegate()
    app.delegate = delegate

    // Menu bar only: no Dock icon. LSUIElement in Info.plist does the same for the
    // bundled app; this covers `swift run` during development.
    app.setActivationPolicy(.accessory)
    app.run()
}
