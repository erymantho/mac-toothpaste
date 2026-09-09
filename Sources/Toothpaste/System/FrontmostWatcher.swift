import AppKit
import Combine

/// Tracks which application would receive a paste right now.
///
/// This replaced `FocusRestore`, which captured the frontmost app once when the panel
/// appeared. That was correct while the panel was transient — it closed the moment you
/// chose something. Since the panel stays open you can activate another window while
/// looking at it, and a captured value then names the wrong app and, worse, predicts
/// the wrong typing profile.
///
/// Our own panel is a non-activating window, so activating it does not make Toothpaste
/// frontmost and the tracked app keeps pointing at the real destination.
@MainActor
final class FrontmostWatcher: ObservableObject {
    @Published private(set) var app: NSRunningApplication?

    private var observer: Any?

    init() {
        app = resolve()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.app = self?.resolve() }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Ignores ourselves: if Toothpaste does become frontmost — opening Settings does
    /// activate it — the last real destination is the more useful answer.
    private func resolve() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else { return app }
        return frontmost
    }
}
