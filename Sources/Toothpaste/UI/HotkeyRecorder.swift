import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, press a combination, done.
///
/// The recorder lives in the settings window, where the app has real focus, so a
/// **local** event monitor is enough to swallow the keystroke. Returning nil from it
/// consumes the event, which is what stops ⌘Q from quitting the app while you are
/// trying to record it. A global recorder would be a different and much harder
/// problem; this one is not.
struct HotkeyRecorder: View {
    @Binding var combo: KeyCombo
    /// Reports what happened when the new combination was registered, so a rejection
    /// is visible rather than leaving a dead shortcut behind.
    var onRecorded: (KeyCombo) -> String?

    @State private var recording = false
    @State private var monitor: Any?

    /// Only ever holds something the button cannot show by itself. A "now ⌃⌥B"
    /// confirmation was there first and was pure duplication: the button had already
    /// changed to ⌃⌥B.
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button(recording ? "press a combination…" : combo.description) {
                    if recording { stop() } else { start() }
                }
                .font(.system(.body, design: .monospaced))

                if recording {
                    Button("cancel") { stop() }
                } else {
                    Button("reset") { apply(.fallback) }
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(recording ? Color.secondary : Color.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard !recording else { return }
        recording = true
        message = "Esc to cancel"
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Modifier-only events are swallowed too, so holding ⌘ does not leak into
            // the window while you are reaching for the rest of the combination.
            guard event.type == .keyDown else { return nil }

            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            if let captured = KeyCombo(event: event) {
                stop()
                apply(captured)
            } else {
                message = "needs ⌘, ⌃ or ⌥ — Shift alone would swallow ordinary typing"
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        if message == "Esc to cancel" { message = nil }
    }

    private func apply(_ candidate: KeyCombo) {
        guard candidate != combo else {
            message = "that is already the shortcut"
            return
        }
        if let problem = onRecorded(candidate) {
            message = problem
        } else {
            combo = candidate
            message = nil
        }
    }
}
