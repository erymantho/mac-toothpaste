import AppKit
import Carbon.HIToolbox

/// What the typing engine would post, checked without posting anything. Compiled with the
/// app's own TypingEngine.swift by `verify-typing.sh`.
///
/// The `CGEvent` class below shadows CoreGraphics' one for every file in this module, the
/// engine's included, so each event it builds lands in a list instead of on the system. The
/// script refuses to run the binary if it links the functions that create or post a real
/// keyboard event, so a shadow that stopped applying cannot turn into keystrokes.
final class CGEvent {
    struct Posted { let key: CGKeyCode; let down: Bool; let flags: CGEventFlags }
    static var posted: [Posted] = []
    private let key: CGKeyCode
    private let down: Bool
    var flags: CGEventFlags = []

    init?(keyboardEventSource: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {
        key = virtualKey
        down = keyDown
    }
    func post(tap: CGEventTapLocation) { Self.posted.append(Posted(key: key, down: down, flags: flags)) }
    func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UniChar>?) {}
}

/// In place of Accessibility.swift: the engine types nothing for an untrusted process.
enum Accessibility { static var isTrustedNow: Bool { true } }

@main
struct VerifyTyping {
    @MainActor
    static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "pass  \(what)" : "FAIL  \(what)")
            if !ok { failures += 1 }
        }
        /// keycode, ↓ or ↑, and the event's flags in hex: 0x20000 is Shift, 0x80000 Option,
        /// and 0x2 and 0x20 the left-Shift and left-Option bits a real keyboard sends.
        func render(_ events: [CGEvent.Posted]) -> String {
            events.map { "\($0.key)\($0.down ? "↓" : "↑")0x\(String($0.flags.rawValue, radix: 16))" }
                .joined(separator: " ")
        }
        let engine = TypingEngine()
        func typed(_ text: String, _ base: TargetProfile, layout: String) async -> [CGEvent.Posted] {
            var profile = base
            profile.layoutSourceID = layout
            profile.initialDelayMs = 0; profile.characterDelayMs = 0; profile.modifierDelayMs = 0
            CGEvent.posted = []
            _ = await engine.type(text, using: profile)
            return CGEvent.posted
        }

        // Windows via RDP on U.S.: Shift is a key event of its own, and every event while it
        // is down says which Shift (0x2) beside the generic flag. Windows App 11.4 releases a
        // Shift that does not say which, so `#` arrived as `3` — CLAUDE.md gotcha 4.
        let shifted = await typed("A#", .windowsRemote, layout: "com.apple.keylayout.US")
        print("A# over RDP: \(render(shifted))")
        check(render(shifted) == "56↓0x20002 0↓0x20002 0↑0x20002 56↑0x0 56↓0x20002 20↓0x20002 20↑0x20002 56↑0x0",
              "Shift is pressed as a key, with the left-Shift bit on it and on the key between")
        let plain = await typed("a3", .windowsRemote, layout: "com.apple.keylayout.US")
        check(render(plain) == "0↓0x0 0↑0x0 20↓0x0 20↑0x0", "an unshifted key carries no modifier at all")

        // Mac apps on U.S.: Option the same way, with the left-Option bit (0x20).
        let option = await typed("åÅ", .local, layout: "com.apple.keylayout.US")
        print("åÅ locally:  \(render(option))")
        check(render(option) == "58↓0x80020 0↓0x80020 0↑0x80020 58↑0x0 56↓0x20002 58↓0xa0022 0↓0xa0022 0↑0xa0022 58↑0x20002 56↑0x0",
              "Option is pressed as a key, with the left-Option bit, and released in reverse order")
        check(CGEvent.posted.allSatisfy { event in
            (!event.flags.contains(.maskShift) || event.flags.rawValue & 0x2 != 0)
                && (!event.flags.contains(.maskAlternate) || event.flags.rawValue & 0x20 != 0)
        }, "no event says Shift or Option without saying which")

        // A newline is the Return key, not a character: gotcha 5. Windows ends a line with
        // \r\n, which Swift reads as one Character that is not equal to "\n".
        let lines = await typed("a\nb", .windowsRemote, layout: "com.apple.keylayout.US")
        check(render(lines) == "0↓0x0 0↑0x0 36↓0x0 36↑0x0 11↓0x0 11↑0x0", "a newline is typed as Return")
        for profile in [TargetProfile.windowsRemote, .local] {
            let windows = await typed("a\r\nb", profile, layout: "com.apple.keylayout.US")
            check(render(windows) == "0↓0x0 0↑0x0 36↓0x0 36↑0x0 11↓0x0 11↑0x0",
                  "a Windows line ending is typed as Return too, with \(profile.name)")
        }

        print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
