import AppKit
import Carbon.HIToolbox

/// Builds the real `KeyboardLayout` maps for a fixed set of layouts and checks them two ways:
/// against `verify-layout.golden`, which says exactly what changed, and against the rules from
/// CLAUDE.md gotcha 4, which have to hold whatever Apple does to a layout. Compiled against the
/// app's own KeyboardLayout.swift and TargetProfile.swift by `verify-layout.sh`.
///
/// It builds maps and reads them, nothing more: no event is posted, no permission is needed,
/// and neither this Mac's layout nor its keyboard plays a part. Every layout is looked up by
/// its ID, enabled or not, and the keyboard type is pinned below.

// MARK: - The keyboard type

/// A layout holds several tables, and `UCKeyTranslate` reads the one for the physical keyboard
/// it is told about. `KeyboardLayout.build` asks `LMGetKbdType()` — the keyboard used last —
/// so after a Japanese keyboard U.S., ABC and U.S. International – PC map differently: measured,
/// the 65 JIS types of 256 give other maps, every ANSI and ISO type the same one, on every
/// layout here. A function of that name in this module shadows Carbon's, inside
/// KeyboardLayout.swift as well, so every Mac gets the same answer. 40 is an ANSI keyboard.
let pinnedKeyboardType: UInt8 = 40
var keyboardTypeQueries = 0
func LMGetKbdType() -> UInt8 {
    keyboardTypeQueries += 1
    return pinnedKeyboardType
}

// MARK: - What is checked

/// Layouts that come with macOS, in AppleKeyboardLayouts.bundle, so every Mac has them whether
/// or not anyone enabled them. U.S. is what "Windows via RDP" maps against; U.S. International
/// – PC puts its accents on dead keys without Option; the rest put a lot on Option.
let layouts = [
    "com.apple.keylayout.US",
    "com.apple.keylayout.USInternational-PC",
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.British",
    "com.apple.keylayout.German",
    "com.apple.keylayout.SwissGerman",
    "com.apple.keylayout.French",
    "com.apple.keylayout.Belgian",
]

let printableASCII: [Character] = (0x20...0x7E).map { Character(Unicode.Scalar(UInt8($0))) }

/// Printable ASCII, tab, and the non-ASCII characters most likely to turn up in a password or
/// a European name. Changing this list changes the golden file.
let characters: [Character] = printableASCII + Array(
    "\táàâäãåéèêëíìîïóòôöõúùûüñçÿæøœßÁÀÂÄÉÈÊËÖÜÑÇÅØ€£¥¢§°´¨ˆ˜¸µ±²³¿¡«»„“”‘’–—…•©®™¬"
)

struct Variant: Hashable {
    let layout: String
    let allowOption: Bool
    var name: String { short(layout) + (allowOption ? "/option" : "/no-option") }
}

func short(_ id: String) -> String {
    id.hasPrefix("com.apple.keylayout.") ? String(id.dropFirst("com.apple.keylayout.".count)) : id
}

// MARK: - Reading a stroke

/// The key at that position on a U.S. ANSI keyboard, so a keycode reads as a place on the
/// keyboard rather than as a number. The character it types depends on the layout.
let keyNames: [Int: String] = {
    var names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`", kVK_ISO_Section: "ISO-§", kVK_JIS_Yen: "JIS-¥",
        kVK_JIS_Underscore: "JIS-_", kVK_JIS_KeypadComma: "JIS-keypad-,",
        kVK_JIS_Eisu: "eisu", kVK_JIS_Kana: "kana",
        kVK_Space: "space", kVK_Tab: "tab", kVK_Return: "return", kVK_Delete: "delete",
        kVK_ForwardDelete: "forward-delete", kVK_Escape: "escape", kVK_Help: "help",
        kVK_Home: "home", kVK_End: "end", kVK_PageUp: "page-up", kVK_PageDown: "page-down",
        kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up", kVK_DownArrow: "down",
        kVK_Command: "command", kVK_RightCommand: "right-command", kVK_Shift: "shift",
        kVK_RightShift: "right-shift", kVK_Option: "option", kVK_RightOption: "right-option",
        kVK_Control: "control", kVK_RightControl: "right-control", kVK_CapsLock: "caps-lock",
        kVK_Function: "fn",
        kVK_ANSI_KeypadDecimal: "keypad-.", kVK_ANSI_KeypadMultiply: "keypad-*",
        kVK_ANSI_KeypadPlus: "keypad-+", kVK_ANSI_KeypadClear: "keypad-clear",
        kVK_ANSI_KeypadDivide: "keypad-/", kVK_ANSI_KeypadEnter: "keypad-enter",
        kVK_ANSI_KeypadMinus: "keypad--", kVK_ANSI_KeypadEquals: "keypad-=",
    ]
    let keypadDigits = [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
                        kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
                        kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
    for (digit, code) in keypadDigits.enumerated() { names[code] = "keypad-\(digit)" }
    let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
                        kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17,
                        kVK_F18, kVK_F19, kVK_F20]
    for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
    return names
}()

/// The keys that only modify another. `UCKeyTranslate` lets any of them flush a pending dead
/// key; pressing one in a real app does nothing of the sort.
let modifierKeys: Set<Int> = [
    kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
    kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
]

/// The numeric keypad, Japan's keypad comma included. A remote machine does not expect keypad
/// scancodes for text.
let keypadKeys: Set<Int> = [
    kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
    kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
    kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
    kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    kVK_JIS_KeypadComma,
]

func key(_ code: CGKeyCode) -> String {
    keyNames[Int(code)].map { "\(code)(\($0))" } ?? "\(code)"
}

func held(_ flags: CGEventFlags) -> String {
    var parts: [String] = []
    var rest = flags.rawValue
    if flags.contains(.maskShift) { parts.append("shift"); rest &= ~CGEventFlags.maskShift.rawValue }
    if flags.contains(.maskAlternate) { parts.append("option"); rest &= ~CGEventFlags.maskAlternate.rawValue }
    if rest != 0 { parts.append(String(format: "flags-0x%llx", rest)) }
    return parts.map { $0 + "+" }.joined()
}

func render(_ stroke: KeyStroke?) -> String {
    switch stroke {
    case .direct(let code, let flags)?:
        return held(flags) + key(code)
    case .composed(let dead, let deadFlags, let base, let baseFlags)?:
        return held(deadFlags) + key(dead) + " then " + held(baseFlags) + key(base)
    case nil:
        return "unreachable"
    }
}

func codePoint(_ character: Character) -> String {
    character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ",")
}

func glyph(_ character: Character) -> String {
    switch character {
    case " ": return "space"
    case "\t": return "tab"
    default: return String(character)
    }
}

/// Padded to a column, and never run into the next one.
func pad(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(1, width - text.count))
}

/// How a problem names a character: `é (U+00E9)`.
func named(_ character: Character) -> String { "\(glyph(character)) (\(codePoint(character)))" }

func keys(of stroke: KeyStroke) -> [CGKeyCode] {
    switch stroke {
    case .direct(let code, _): return [code]
    case .composed(let dead, _, let base, _): return [dead, base]
    }
}

func flags(of stroke: KeyStroke) -> [CGEventFlags] {
    switch stroke {
    case .direct(_, let flags): return [flags]
    case .composed(_, let deadFlags, _, let baseFlags): return [deadFlags, baseFlags]
    }
}

// MARK: - The layout itself, read independently of KeyboardLayout

/// The layout's own data, so the rules below can ask `UCKeyTranslate` directly what a stroke
/// types instead of trusting the map that is being checked.
struct LayoutData {
    let data: Data

    init?(_ id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    /// What one key press types, and the dead-key state it leaves behind. Dead keys stay on,
    /// options 0, as in KeyboardLayout.build: a dead key alone types nothing, which is what
    /// "one key types this character on its own" below has to mean.
    func type(_ code: Int, _ flags: CGEventFlags, state: inout UInt32) -> String {
        var modifiers = 0
        if flags.contains(.maskShift) { modifiers |= shiftKey }
        if flags.contains(.maskAlternate) { modifiers |= optionKey }
        if flags.contains(.maskControl) { modifiers |= controlKey }
        if flags.contains(.maskCommand) { modifiers |= cmdKey }
        var current = state
        let typed: String = data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return "" }
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDown), UInt32(modifiers >> 8),
                UInt32(pinnedKeyboardType), 0,
                &current, 8, &length, &chars
            )
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
        }
        state = current
        return typed
    }

    /// FNV-1a over the layout's bytes. When the map changes, this says whether the layout did.
    var fingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(format: "%016llx", hash)
    }
}

/// Pending means the LOW 16 bits: the high word only remembers the dead key just consumed.
func pending(_ state: UInt32) -> Bool { state & 0xFFFF != 0 }

// MARK: - Run

@main
struct VerifyLayout {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            print("usage: verify-layout <file to write the map to>")
            exit(2)
        }
        var failures = 0
        func check(_ problems: [String], _ what: String) {
            print(problems.isEmpty ? "pass  \(what)" : "FAIL  \(what)")
            for problem in problems.prefix(6) { print("        \(problem)") }
            if problems.count > 6 { print("        and \(problems.count - 6) more") }
            if !problems.isEmpty { failures += 1 }
        }

        // What the default profiles map against. A profile without a layout uses the Mac's own,
        // and every layout here stands in for it — which is what keeps this Mac out of it.
        var golden: [Variant] = []
        var notes: [String] = []
        for profile in TargetProfile.builtIns {
            let ids = profile.layoutSourceID.map { [$0] } ?? layouts
            for id in ids where !golden.contains(Variant(layout: id, allowOption: profile.allowOption)) {
                golden.append(Variant(layout: id, allowOption: profile.allowOption))
            }
            let over = profile.layoutSourceID.map(short) ?? "the Mac's own layout, which every one below stands in for"
            notes.append("\(profile.name): \(over); Option \(profile.allowOption ? "allowed" : "forbidden")")
        }
        let allLayouts = layouts + golden.map(\.layout).filter { !layouts.contains($0) }
        let rank = { (variant: Variant) in (allLayouts.firstIndex(of: variant.layout) ?? 0) * 2 + (variant.allowOption ? 0 : 1) }
        golden.sort { rank($0) < rank($1) }

        // Every layout both ways, for the rules; the golden file holds the defaults' share.
        var maps: [Variant: KeyboardLayout] = [:]
        var data: [String: LayoutData] = [:]
        var missing: [String] = []
        for id in allLayouts {
            guard let layoutData = LayoutData(id) else {
                missing.append("\(id) is not on this Mac")
                continue
            }
            guard let withOption = KeyboardLayout.build(sourceID: id, allowOption: true),
                  let withoutOption = KeyboardLayout.build(sourceID: id, allowOption: false)
            else {
                missing.append("\(id) is on this Mac, but KeyboardLayout does not find it")
                continue
            }
            data[id] = layoutData
            maps[Variant(layout: id, allowOption: true)] = withOption
            maps[Variant(layout: id, allowOption: false)] = withoutOption
        }
        let every = maps.keys.sorted { rank($0) < rank($1) }

        // "27.0.1 (26A434)". Not compared: the report names it when a layout's bytes moved.
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "").replacingOccurrences(of: "Build ", with: "")
        var dump = """
        # What KeyboardLayout.build makes of a fixed set of characters: one line per map and
        # character, giving the keys pressed: keycode, and in parentheses the key at that place on
        # a U.S. keyboard. Written by `scripts/verify-layout.sh --update`; lines starting with #
        # are not compared. Keyboard type pinned to \(pinnedKeyboardType) (ANSI).
        # macOS \(macOS)

        """
        for note in notes { dump += "# \(note)\n" }
        for id in allLayouts {
            if let layoutData = data[id] {
                dump += "# data \(short(id)) \(layoutData.data.count) bytes fnv1a64 \(layoutData.fingerprint)\n"
            }
        }
        for variant in golden {
            guard let map = maps[variant] else { continue }
            let label = pad(variant.name, 26)
            dump += "\(label)reachable \(map.reachableCount)\n"
            for character in characters {
                dump += "\(label)\(pad(codePoint(character), 8))\(pad(glyph(character), 6))\(render(map[character]))\n"
            }
        }
        do {
            try dump.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        } catch {
            print("cannot write the map: \(error)")
            exit(2)
        }

        print("=== the setup ===")
        check(missing, "KeyboardLayout finds every layout here, enabled or not")
        check(keyboardTypeQueries > 0 ? [] : ["KeyboardLayout no longer asks LMGetKbdType(), so the pin above does nothing"],
              "the keyboard type is the pinned one, not whichever keyboard was used last")

        /// The two maps of one layout, Option forbidden first, each with its name.
        func both(_ id: String) -> [(name: String, map: KeyboardLayout)] {
            [false, true].compactMap { allowOption in
                let variant = Variant(layout: id, allowOption: allowOption)
                return maps[variant].map { (variant.name, $0) }
            }
        }
        /// Characters whose stroke is not the one given, in both maps of a layout.
        func differ(_ id: String, _ expected: [(Character, KeyStroke)]) -> [String] {
            both(id).flatMap { name, map in
                expected.compactMap { character, stroke in
                    map[character] == stroke ? nil
                        : "\(name) \(named(character)) is \(render(map[character])), not \(render(stroke))"
                }
            }
        }

        print("\n=== U.S., what \"Windows via RDP\" maps against ===")
        check(both("com.apple.keylayout.US").flatMap { name, map in
            printableASCII.compactMap { character in
                if case .direct(_, let flags)? = map[character], !flags.contains(.maskAlternate) { return nil }
                return "\(name) \(named(character)) is \(render(map[character]))"
            }
        }, "printable ASCII is all one key press without Option, Option allowed or not")
        if let map = maps[Variant(layout: "com.apple.keylayout.US", allowOption: false)] {
            let composed = characters.filter { if case .composed? = map[$0] { return true } else { return false } }
            let guessed = Array("éü€").filter { map[$0] != nil }
            check(composed.map { "\(named($0)) is \(render(map[$0]))" }
                  + guessed.map { "\(named($0)) is \(render(map[$0])), on a remote with no such key" },
                  "without Option nothing is composed, so é ü € are reported rather than guessed")
        }

        // Gotcha 4's own list. The backtick is not on it: with Option allowed this layout has a
        // key for it, and one key press rightly beats a dead key.
        print("\n=== U.S. International – PC, where the accents are dead keys ===")
        let space = CGKeyCode(kVK_Space), quote = CGKeyCode(kVK_ANSI_Quote)
        check(differ("com.apple.keylayout.USInternational-PC", [
            ("\"", .composed(quote, .maskShift, space, [])),
            ("'", .composed(quote, [], space, [])),
            ("^", .composed(CGKeyCode(kVK_ANSI_6), .maskShift, space, [])),
            ("~", .composed(CGKeyCode(kVK_ANSI_Grave), .maskShift, space, [])),
        ]), "\" ' ^ ~ are each their dead key, then space, Option allowed or not")
        check(differ("com.apple.keylayout.USInternational-PC", [
            ("é", .composed(quote, [], CGKeyCode(kVK_ANSI_E), [])),
            ("ü", .composed(quote, .maskShift, CGKeyCode(kVK_ANSI_U), [])),
        ]), "é is the acute dead key then e, ü the diaeresis then u, Option allowed or not")

        print("\n=== every layout, Option allowed and forbidden ===")
        var holdsOption: [String] = [], holdsOther: [String] = [], modifierCompletes: [String] = []
        var keypad: [String] = [], replay: [String] = [], order: [String] = [], listed: [String] = []
        for variant in every {
            guard let map = maps[variant], let layoutData = data[variant.layout] else { continue }
            let allowed: [CGEventFlags] = variant.allowOption
                ? [[], .maskShift, .maskAlternate, [.maskShift, .maskAlternate]] : [[], .maskShift]

            // What Settings → Layout check shows before a password goes to a remote machine.
            let lacking = characters.filter { map[$0] == nil }
            let shown = map.unproducible(in: "a\n" + String(characters))
            if shown != lacking {
                listed.append("\(variant.name) lists \(String(shown).debugDescription), lacks \(String(lacking).debugDescription)")
            }

            for character in characters {
                guard let stroke = map[character] else { continue }
                let what = "\(variant.name) \(named(character)) is \(render(stroke))"

                if !variant.allowOption, flags(of: stroke).contains(where: { $0.contains(.maskAlternate) }) {
                    holdsOption.append(what)
                }
                if flags(of: stroke).contains(where: { !$0.subtracting([.maskShift, .maskAlternate]).isEmpty }) {
                    holdsOther.append(what)
                }
                if case .composed(_, _, let base, _) = stroke, modifierKeys.contains(Int(base)) {
                    modifierCompletes.append(what)
                }
                if keys(of: stroke).contains(where: { keypadKeys.contains(Int($0)) }) {
                    keypad.append(what)
                }

                // Replayed the way a real app receives it: dead keys live, from a clean state.
                var state: UInt32 = 0
                switch stroke {
                case .direct(let code, let flags):
                    let typed = layoutData.type(Int(code), flags, state: &state)
                    if pending(state) { replay.append("\(what), which is a dead key: it types nothing yet") }
                    else if typed != String(character) { replay.append("\(what), which types \(typed.debugDescription)") }
                case .composed(let dead, let deadFlags, let base, let baseFlags):
                    let first = layoutData.type(Int(dead), deadFlags, state: &state)
                    if !first.isEmpty || !pending(state) {
                        replay.append("\(what), but the first key types \(first.debugDescription) and is no dead key")
                        break
                    }
                    let typed = layoutData.type(Int(base), baseFlags, state: &state)
                    if pending(state) { replay.append("\(what), which leaves a dead key pending for the next character") }
                    else if typed != String(character) { replay.append("\(what), which types \(typed.debugDescription)") }
                }

                // Fewest modifiers first: the first combination, in the order allowed lists them,
                // in which one key types this character on its own.
                let best = allowed.firstIndex { flags in
                    (0..<128).contains { code in
                        guard !keypadKeys.contains(code) else { return false }
                        var state: UInt32 = 0
                        return layoutData.type(code, flags, state: &state) == String(character)
                    }
                }
                switch (stroke, best) {
                case (.direct(_, let flags), let best?) where flags == allowed[best]:
                    break
                case (.composed, nil):
                    break
                case (_, let best?):
                    order.append("\(what), where \(held(allowed[best]))one key would do")
                case (.direct, nil):
                    order.append("\(what), which no single key in the allowed combinations types")
                }
            }
        }
        check(holdsOption, "with Option forbidden, no stroke holds Option")
        check(holdsOther, "no stroke holds anything but Shift and Option, the only two the engine presses")
        check(modifierCompletes, "no dead key is completed by a modifier key")
        check(keypad, "no stroke uses the numeric keypad")
        check(replay, "every stroke, replayed through UCKeyTranslate, types its character and leaves no dead key pending")
        check(order, "fewest modifiers first: none, Shift, Option, both, and a dead key only when no single key will do")
        check(listed, "Layout check lists exactly what a map lacks, and never the newline Return types")

        // The other direction: the panel's search is not a text field, so nothing composes
        // its dead keys but KeyComposer, which asks the layout the same way a text field would.
        print("\n=== the search's dead keys, composed by KeyComposer ===")
        func typed(_ id: String, _ keys: [(Int, NSEvent.ModifierFlags)]) -> String {
            let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let source = (TISCreateInputSourceList(filter, true)?.takeRetainedValue()
                    as? [TISInputSource])?.first
            else { return "no layout \(short(id))" }
            var composer = KeyComposer()
            return keys.map { code, flags in
                composer.characters(keyCode: UInt16(code), modifiers: flags, layout: source) ?? "nil"
            }.joined(separator: "|")
        }
        let international = "com.apple.keylayout.USInternational-PC", us = "com.apple.keylayout.US"
        let searches: [(layout: String, keys: [(Int, NSEvent.ModifierFlags)], expected: String, what: String)] = [
            (international, [(kVK_ANSI_Quote, []), (kVK_ANSI_E, [])], "|é", "' then e"),
            (international, [(kVK_ANSI_Quote, []), (kVK_Space, [])], "|'", "' then space"),
            (international, [(kVK_ANSI_Quote, []), (kVK_ANSI_T, [])], "|'t", "' then t"),
            (international, [(kVK_ANSI_Quote, [.shift]), (kVK_ANSI_U, [])], "|ü", "\" then u"),
            (international, [(kVK_ANSI_Quote, []), (kVK_ANSI_E, []), (kVK_ANSI_E, [])], "|é|e", "é, then a plain e"),
            (international, [(kVK_ANSI_2, [.shift, .option])], "€", "⇧⌥2"),
            (us, [(kVK_ANSI_E, [.option]), (kVK_ANSI_E, [])], "|é", "⌥e then e"),
            (us, [(kVK_ANSI_E, [.option]), (kVK_Space, [])], "|´", "⌥e then space"),
            (us, [(kVK_ANSI_A, [.shift])], "A", "⇧a"),
        ]
        check(searches.compactMap { search in
            let got = typed(search.layout, search.keys)
            return got == search.expected ? nil
                : "\(short(search.layout)) \(search.what) typed \(got.debugDescription), not \(search.expected.debugDescription)"
        }, "a dead key waits for the next key: é, or the accent and the letter; ⇧⌥2 is €")

        print(failures == 0 ? "\nall rules hold" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
