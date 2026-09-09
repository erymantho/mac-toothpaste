import AppKit
import Carbon.HIToolbox

/// How one character is produced on a keyboard layout.
enum KeyStroke: Equatable {
    /// One key, optionally with modifiers held.
    case direct(CGKeyCode, CGEventFlags)
    /// A dead key, then a key that completes it: `^` is dead-circumflex then space,
    /// `é` is dead-acute then `e`.
    case composed(CGKeyCode, CGEventFlags, CGKeyCode, CGEventFlags)
}

/// A character → keystroke map built from one specific keyboard layout.
///
/// Which layout is not a detail. We turn characters into keycodes, macOS turns those
/// into scancodes, and for a remote session the *remote machine* turns them back into
/// characters with *its own* layout. Mapping against the Mac's active layout is only
/// correct when the two agree — measured the hard way, see PLAN.md section 3.
struct KeyboardLayout {
    let name: String
    let sourceID: String?
    private let strokes: [Character: KeyStroke]

    subscript(character: Character) -> KeyStroke? { strokes[character] }
    var reachableCount: Int { strokes.count }

    /// Characters in `text` this layout cannot produce at all.
    func unproducible(in text: String) -> [Character] {
        text.filter { $0 != "\n" && strokes[$0] == nil }
    }

    // MARK: - Building

    /// - Parameters:
    ///   - sourceID: input-source id (e.g. `com.apple.keylayout.US`), or nil for the
    ///     Mac's active layout.
    ///   - allowOption: include Option combinations. Must be **false** for Windows
    ///     targets: macOS puts accents on option-key dead keys, Windows has no
    ///     equivalent, and Alt there is a menu accelerator.
    static func build(sourceID: String?, allowOption: Bool) -> KeyboardLayout? {
        guard let resolved = resolve(sourceID: sourceID) else { return nil }

        var strokes: [Character: KeyStroke] = [:]
        let keyboardType = UInt32(LMGetKbdType())

        // The keypad produces the same characters as the main rows and comes first in
        // keycode order — a remote machine does not expect keypad scancodes for text.
        let keypad: Set<Int> = [
            kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
            kVK_ANSI_KeypadClear, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter,
            kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
            kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
            kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
            kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
        ]

        // Modifiers outermost so unmodified keys claim their character first —
        // otherwise 'a' maps to some option combination instead of key 0.
        var combos: [(UInt32, CGEventFlags)] = [
            (0, []),
            (UInt32(shiftKey >> 8), .maskShift),
        ]
        if allowOption {
            combos.append((UInt32(optionKey >> 8), .maskAlternate))
            combos.append((UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate]))
        }

        resolved.data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return }

            func translate(
                _ keyCode: Int, _ carbonModifiers: UInt32, state: inout UInt32, keepDeadKeys: Bool
            ) -> String {
                var length = 0
                var chars = [UniChar](repeating: 0, count: 8)
                let options = keepDeadKeys ? OptionBits(0) : OptionBits(kUCKeyTranslateNoDeadKeysBit)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDown), carbonModifiers,
                    keyboardType, options, &state, 8, &length, &chars
                )
                guard status == noErr, length > 0 else { return "" }
                return String(utf16CodeUnits: chars, count: length)
            }

            // Pass 1 — single key press.
            var characterKeys: Set<Int> = []
            for (carbonModifiers, cgFlags) in combos {
                for keyCode in 0..<128 where !keypad.contains(keyCode) {
                    var state: UInt32 = 0
                    let produced = translate(keyCode, carbonModifiers, state: &state, keepDeadKeys: false)
                    guard produced.count == 1, let character = produced.first else { continue }
                    characterKeys.insert(keyCode)
                    if strokes[character] == nil {
                        strokes[character] = .direct(CGKeyCode(keyCode), cgFlags)
                    }
                }
            }

            // Pass 2 — collect dead keys.
            var deadKeys: [(CGKeyCode, CGEventFlags, UInt32)] = []
            for (carbonModifiers, cgFlags) in combos {
                for keyCode in 0..<128 where !keypad.contains(keyCode) {
                    var state: UInt32 = 0
                    let produced = translate(keyCode, carbonModifiers, state: &state, keepDeadKeys: true)
                    if produced.isEmpty && state != 0 {
                        deadKeys.append((CGKeyCode(keyCode), cgFlags, state))
                    }
                }
            }

            // Pass 3 — compose each dead key with a following character key.
            for (deadCode, deadFlags, deadState) in deadKeys {
                for (carbonModifiers, cgFlags) in combos {
                    // Only real character keys. A modifier keycode also "flushes" the
                    // pending accent as far as UCKeyTranslate is concerned, but
                    // pressing Right Command does nothing of the sort in a real app.
                    for keyCode in 0..<128 where characterKeys.contains(keyCode) {
                        var state = deadState
                        let produced = translate(keyCode, carbonModifiers, state: &state, keepDeadKeys: true)
                        // Only the LOW 16 bits mean "a dead key is still pending"; the
                        // high word remembers the one just consumed, so a successful
                        // composition reports e.g. 0x40000, not 0. Getting this wrong
                        // picks a pairing that leaks the accent into the next
                        // character and eats the following space.
                        guard state & 0xFFFF == 0, produced.count == 1,
                              let character = produced.first
                        else { continue }
                        if strokes[character] == nil {
                            strokes[character] = .composed(deadCode, deadFlags, CGKeyCode(keyCode), cgFlags)
                        }
                    }
                }
            }
        }

        return KeyboardLayout(name: resolved.name, sourceID: sourceID, strokes: strokes)
    }

    // MARK: - Layout lookup

    private static func read(_ source: TISInputSource) -> (data: Data, name: String)? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
        return (data, name)
    }

    private static func resolve(sourceID: String?) -> (data: Data, name: String)? {
        if let sourceID {
            let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
            // includeAllInstalled: nobody enables the remote machine's layout on their
            // own Mac just to be able to type into it.
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                    as? [TISInputSource],
                  let source = list.first
            else { return nil }
            return read(source)
        }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        else { return nil }
        return read(source)
    }

    /// Installed layouts, for the settings picker.
    static func installedLayouts() -> [(id: String, name: String)] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.compactMap { source in
            guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil,
                  let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let namePointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            else { return nil }
            return (
                Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String,
                Unmanaged<CFString>.fromOpaque(namePointer).takeUnretainedValue() as String
            )
        }
    }
}
