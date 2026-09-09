import AppKit
import Carbon.HIToolbox

/// A global shortcut: one key plus its modifiers, in the Carbon flavour that
/// `RegisterEventHotKey` expects.
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let fallback = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    /// Builds a combo from a recorded key press, or refuses it.
    ///
    /// At least one of Command, Control or Option is required. Shift alone would make a
    /// shortcut out of an ordinary capital letter and swallow it everywhere.
    init?(event: NSEvent) {
        var carbon: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        guard carbon & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// How macOS writes it: modifiers in ⌃⌥⇧⌘ order, then the key.
    var description: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.name(for: keyCode)
    }

    /// Keys that have a name rather than a character. Everything else is asked of the
    /// current keyboard layout, because which character a keycode produces depends on
    /// it — the key next to Z is not `Z` on every layout.
    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func name(for keyCode: UInt32) -> String {
        if let named = named[Int(keyCode)] { return named }

        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "key \(keyCode)" }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var result = "key \(keyCode)"
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, 4, &length, &chars
            )
            guard status == noErr, length > 0 else { return }
            result = String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return result
    }
}
