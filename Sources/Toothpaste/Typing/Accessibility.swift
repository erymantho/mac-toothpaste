import AppKit
import ApplicationServices
import Combine

/// `CGEvent.post` silently does nothing without this permission — no error, no
/// exception, just no typing. Every path that types must check first.
@MainActor
final class Accessibility: ObservableObject {
    @Published private(set) var isTrusted: Bool

    private var timer: Timer?

    static var isTrustedNow: Bool { AXIsProcessTrusted() }

    init() {
        isTrusted = AXIsProcessTrusted()
        // There is no notification when a TCC decision changes, so the state has to be
        // polled. Two seconds is fast enough to feel immediate when someone flips the
        // switch in System Settings while our window is open.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let current = AXIsProcessTrusted()
                if current != self.isTrusted { self.isTrusted = current }
            }
        }
    }

    /// Shows the system prompt. macOS presents it at most once per app, so calling it
    /// repeatedly is not a way to nag someone into granting it.
    @discardableResult
    static func requestPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Reveals the running app in Finder.
    ///
    /// Worth having because the grant applies to *one* bundle. Building this project
    /// leaves a second copy in `dist/`, and granting the permission to that one — which
    /// every build deletes and recreates — is how an afternoon gets lost.
    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Where the running app lives, shortened for display.
    static var bundleLocation: String {
        let path = Bundle.main.bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// True when this is a build-directory copy rather than an installed one.
    ///
    /// Not a permission problem — a stable signing certificate means TCC treats every
    /// copy with the same bundle id and certificate as the same app, wherever it sits.
    /// It matters because `SMAppService` launch-at-login points at a path, and this one
    /// is deleted on every build.
    static var isRunningFromBuildDirectory: Bool {
        let parts = Bundle.main.bundleURL.pathComponents
        return parts.contains("dist") || parts.contains(".build")
    }

    /// Debug only: forces the not-yet-granted rendering on a machine where the
    /// permission is already in place, so that screen can be checked without revoking
    /// anything. Kept because the alternative costs a real `tccutil reset`.
    static var debugForceUngranted: Bool {
        CommandLine.arguments.contains("--debug-ungranted")
    }

    /// Debug only: opens the onboarding window at launch even when nothing is wrong,
    /// so the granted rendering can be checked.
    static var debugShowOnboarding: Bool {
        CommandLine.arguments.contains("--debug-onboarding") || debugForceUngranted
    }
}
