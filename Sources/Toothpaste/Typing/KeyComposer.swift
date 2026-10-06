import AppKit
import Carbon.HIToolbox

/// Turns the panel search's key presses into text, dead keys included.
///
/// The search is not a text field (see `PanelView`), and composing a dead key with the key
/// after it is the text input system's work, not the key event's: tried by hand, `'` then
/// `e` on U.S. International – PC reached the search as a bare `e`, and the apostrophe on
/// its own not at all. So the search keeps the pending dead key here and asks the layout,
/// through `UCKeyTranslate`, what the next key makes of it — `é`, or the accent and the
/// letter when the two do not combine, which is how that layout types `'t` in `don't`.
struct KeyComposer {
    /// A dead key waiting for the key that completes it, in `UCKeyTranslate`'s own terms.
    private var pending: UInt32 = 0

    mutating func reset() { pending = 0 }

    /// What the key typed on the layout in use: "" while it only started a dead key, nil
    /// when that layout has no key map to ask, which leaves it to the event's characters.
    mutating func characters(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        else { return nil }
        return characters(keyCode: keyCode, modifiers: modifiers, layout: source)
    }

    mutating func characters(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, layout source: TISInputSource
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            pending = 0
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var carbon = 0
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.capsLock) { carbon |= alphaLock }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), UInt32(carbon >> 8) & 0xFF,
                UInt32(LMGetKbdType()), 0, &pending, 8, &length, &chars
            )
        }
        guard status == noErr else {
            pending = 0
            return nil
        }
        // Only the low 16 bits say a dead key is still pending (gotcha 4); the high word
        // remembers the one just used up, and has no business in the next key.
        if pending & 0xFFFF == 0 { pending = 0 }
        return String(utf16CodeUnits: chars, count: length)
    }
}
