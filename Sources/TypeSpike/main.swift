import AppKit
import Carbon.HIToolbox

// Layout and typing diagnostic. Started as a throwaway spike for PLAN.md section 3;
// kept deliberately, because `--dump-map` is the only way to see what a given
// keyboard layout can and cannot produce until the phase 3 settings UI absorbs it.
//
// Answered so far, against Windows App / Devolutions RDM / Omnissa Horizon:
//   - Unicode mode is useless over RDP. The clients read NSEvent.keyCode and ignore
//     the unicode payload, so every character arrives as 'a' (virtual key 0 is
//     kVK_ANSI_A). All three clients behave identically.
//   - Virtual-key mode is the way, but flags on the character event are not enough:
//     modifiers have to be posted as real Shift/Option key events, and dead keys
//     have to be composed rather than falling back to unicode.


let defaultText = #"Hello123 test@example.com "quoted" 'x' é ü € !@#$%^&* {}[]|\ ~end~"#

var mode = "vk"
var delayMs: UInt32 = 20
var modDelayMs: UInt32 = 8
var waitSec: UInt32 = 5
var text = defaultText
var dumpMap = false
var activateBundleID: String?
var layoutSourceID: String?
var listLayouts = false
var noOption = false

var args = Array(CommandLine.arguments.dropFirst())
var positional: [String] = []
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--mode":
        mode = args.isEmpty ? mode : args.removeFirst()
    case "--delay":
        delayMs = args.isEmpty ? delayMs : (UInt32(args.removeFirst()) ?? delayMs)
    case "--mod-delay":
        modDelayMs = args.isEmpty ? modDelayMs : (UInt32(args.removeFirst()) ?? modDelayMs)
    case "--wait":
        waitSec = args.isEmpty ? waitSec : (UInt32(args.removeFirst()) ?? waitSec)
    case "--dump-map":
        dumpMap = true
    case "--activate":
        activateBundleID = args.isEmpty ? nil : args.removeFirst()
    case "--layout":
        layoutSourceID = args.isEmpty ? nil : args.removeFirst()
    case "--list-layouts":
        listLayouts = true
    case "--no-option":
        noOption = true
    case "-h", "--help":
        print("""
        usage: typespike [--mode vk|unicode] [--delay MS] [--mod-delay MS] [--wait SEC] [text]

          --mode vk        real virtual keycodes + real modifier key events (default;
                           the only mode that works over RDP)
          --mode unicode   keyboardSetUnicodeString — fine locally, garbage over RDP
          --delay          milliseconds between characters (default 20)
          --mod-delay      milliseconds around modifier presses (default 8); raise it
                           if a remote session drops shifted characters
          --wait           seconds to focus the target window first (default 5)
          --dump-map       print the layout mapping and exit; types nothing
          --activate ID    bring a bundle id frontmost first, e.g. com.apple.TextEdit
          --layout ID      map against this keyboard layout instead of the active one.
                           Use the REMOTE machine's layout for RDP, e.g.
                           com.apple.keylayout.US — the remote applies its own layout
                           to the scancodes we send, so mapping against the Mac's is
                           only right when the two happen to agree.
          --list-layouts   print installed layout ids and exit
          --no-option      never use Option/Alt combinations. Required for Windows
                           remotes: macOS layouts put accents on option+key, Windows
                           has no equivalent, and Alt there is a menu accelerator.
                           Characters needing Option become unproducible — which is
                           the truth, and better reported than guessed.
        """)
        exit(0)
    default:
        positional.append(arg)
    }
}
if !positional.isEmpty { text = positional.joined(separator: " ") }

guard mode == "unicode" || mode == "vk" else {
    print("error: --mode must be 'vk' or 'unicode'")
    exit(1)
}

// MARK: - How a character is produced

enum KeyStroke {
    /// One key, optionally with modifiers held.
    case direct(CGKeyCode, CGEventFlags)
    /// A dead key, then a second key that completes it — `^` is dead-circumflex then
    /// space; `é` is dead-acute then `e`.
    case composed(CGKeyCode, CGEventFlags, CGKeyCode, CGEventFlags)
}

func readLayout(_ source: TISInputSource) -> (data: Data, name: String)? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
    return (data, name)
}

/// Resolves a layout by input-source id, or the active one when nil.
///
/// This exists because of the one problem no local code can fix: we turn characters
/// into scancodes using a layout, and the *remote* machine turns those scancodes back
/// into characters using *its* layout. Mapping against the Mac's active layout is
/// only correct when the two agree.
func resolveLayout(sourceID: String?) -> (data: Data, name: String)? {
    if let sourceID {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        // includeAllInstalled: the remote's layout is usually not enabled locally.
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first
        else { return nil }
        return readLayout(source)
    }
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
    else { return nil }
    return readLayout(source)
}

func printAvailableLayouts() {
    let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    else { return }
    for source in list {
        guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { continue }
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
        let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
        print("  \(id)   \(name)")
    }
}

func currentLayoutName() -> String {
    (TISCopyCurrentKeyboardInputSource()?.takeRetainedValue())
        .flatMap { TISGetInputSourceProperty($0, kTISPropertyLocalizedName) }
        .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        ?? "unknown"
}

/// Reverse-maps characters to the keystrokes that produce them, using the active
/// keyboard layout. This is what RDP clients understand: they turn the keycode into
/// a scancode for the remote machine.
///
/// Caveat that no local code can fix: the *remote* machine applies its *own* layout
/// to that scancode. This round-trips only if both layouts agree.
func buildKeyMap() -> [Character: KeyStroke] {
    var map: [Character: KeyStroke] = [:]
    guard let resolved = resolveLayout(sourceID: layoutSourceID) else { return map }
    let layoutData = resolved.data
    let keyboardType = UInt32(LMGetKbdType())

    // The numeric keypad produces the same characters as the main rows and comes
    // first in keycode order — a remote machine does not expect keypad scancodes
    // for text.
    let keypad: Set<Int> = [
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
        kVK_ANSI_KeypadClear, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter,
        kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
        kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
        kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    ]

    // Modifiers outermost so unmodified keys claim their character first — otherwise
    // 'a' might get mapped to some option-combination instead of key 0.
    var combos: [(UInt32, CGEventFlags)] = [
        (0, []),
        (UInt32(shiftKey >> 8), .maskShift),
        (UInt32(optionKey >> 8), .maskAlternate),
        (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate]),
    ]
    // A Windows remote cannot reproduce macOS option-key combinations at all, so
    // offering them would just mistype silently.
    if noOption { combos = Array(combos.prefix(2)) }

    layoutData.withUnsafeBytes { raw in
        guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }

        /// Returns the characters a key produces, and the dead-key state it leaves.
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

        // Pass 1 — characters reachable with a single key press.
        var characterKeys: Set<Int> = []
        for (carbonModifiers, cgFlags) in combos {
            for keyCode in 0..<128 where !keypad.contains(keyCode) {
                var state: UInt32 = 0
                let produced = translate(keyCode, carbonModifiers, state: &state, keepDeadKeys: false)
                guard produced.count == 1, let character = produced.first else { continue }
                characterKeys.insert(keyCode)
                if map[character] == nil {
                    map[character] = .direct(CGKeyCode(keyCode), cgFlags)
                }
            }
        }

        // Pass 2 — collect the dead keys.
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

        // Pass 3 — compose each dead key with every following key. Space comes first
        // in practice for the standalone accents (`^` `~` `"` `'`), letters for the
        // accented vowels (`é` `ü`).
        for (deadCode, deadFlags, deadState) in deadKeys {
            for (carbonModifiers, cgFlags) in combos {
                // Only real character keys. A modifier keycode also "flushes" the
                // pending accent as far as UCKeyTranslate is concerned, but pressing
                // Right Command does nothing of the sort in an actual app.
                for keyCode in 0..<128 where characterKeys.contains(keyCode) {
                    var state = deadState
                    let produced = translate(keyCode, carbonModifiers, state: &state, keepDeadKeys: true)
                    // Only the LOW 16 bits say whether a dead key is still pending —
                    // the high word just remembers which dead key was last consumed, so
                    // a successful composition reports e.g. 0x40000, not 0.
                    // This matters: shift+' then ' also yields `"`, but leaves acute
                    // pending, which then got flushed into the next character and ate
                    // the following space (`"quoted" ` came out as `"'quoted"'`).
                    // Requiring a clean low word picks dead-key-then-space instead.
                    guard state & 0xFFFF == 0, produced.count == 1, let character = produced.first
                    else { continue }
                    if map[character] == nil {
                        map[character] = .composed(deadCode, deadFlags, CGKeyCode(keyCode), cgFlags)
                    }
                }
            }
        }
    }

    return map
}

// MARK: - Posting events

func modifierKeys(for flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)] {
    var result: [(CGKeyCode, CGEventFlags)] = []
    // With the left-hand key's device bit beside the generic flag, as a real keyboard
    // sends it (NX_DEVICELSHFTKEYMASK, NX_DEVICELALTKEYMASK). Windows App 11.4 reads the
    // device bit alone — see TypingEngine.press.
    if flags.contains(.maskShift) {
        result.append((CGKeyCode(kVK_Shift), [.maskShift, CGEventFlags(rawValue: 0x02)]))
    }
    if flags.contains(.maskAlternate) {
        result.append((CGKeyCode(kVK_Option), [.maskAlternate, CGEventFlags(rawValue: 0x20)]))
    }
    return result
}

/// Posts one key press.
///
/// The important part for RDP: modifiers go out as **real Shift/Option key events**.
/// Setting `flags` on the character event alone is enough for native Mac apps, but
/// RDP clients track modifier state from the modifier key events themselves — with
/// flags only, `Hello` arrives as `hello` and `@` as `2`.
func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
    let modifiers = modifierKeys(for: flags)
    var held: CGEventFlags = []

    for (modCode, modFlag) in modifiers {
        held.formUnion(modFlag)
        let event = CGEvent(keyboardEventSource: source, virtualKey: modCode, keyDown: true)
        event?.flags = held
        event?.post(tap: .cghidEventTap)
        if modDelayMs > 0 { usleep(modDelayMs * 1000) }
    }

    for isDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
        else { continue }
        event.flags = flags.union(held)
        event.post(tap: .cghidEventTap)
    }

    for (modCode, modFlag) in modifiers.reversed() {
        if modDelayMs > 0 { usleep(modDelayMs * 1000) }
        held.subtract(modFlag)
        let event = CGEvent(keyboardEventSource: source, virtualKey: modCode, keyDown: false)
        event?.flags = held
        event?.post(tap: .cghidEventTap)
    }
}

func postUnicode(_ character: Character, source: CGEventSource?) {
    var utf16 = Array(String(character).utf16)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { return }
    // Clear flags explicitly: modifiers still held from a hotkey would otherwise ride
    // along and corrupt the output.
    down.flags = []
    up.flags = []
    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func typeUnicode(_ text: String, source: CGEventSource?) {
    for character in text {
        if character == "\n" {
            pressKey(CGKeyCode(kVK_Return), flags: [], source: source)
        } else {
            postUnicode(character, source: source)
        }
        usleep(delayMs * 1000)
    }
}

func typeVirtualKeys(_ text: String, source: CGEventSource?) {
    let map = buildKeyMap()
    var skipped: [Character] = []

    for character in text {
        if character == "\n" {
            pressKey(CGKeyCode(kVK_Return), flags: [], source: source)
        } else {
            switch map[character] {
            case .direct(let code, let flags):
                pressKey(code, flags: flags, source: source)
            case .composed(let deadCode, let deadFlags, let baseCode, let baseFlags):
                pressKey(deadCode, flags: deadFlags, source: source)
                usleep(delayMs * 1000)
                pressKey(baseCode, flags: baseFlags, source: source)
            case nil:
                // Deliberately NOT falling back to unicode: over RDP that silently
                // produces 'a'. Dropping the character is the honest failure.
                skipped.append(character)
            }
        }
        usleep(delayMs * 1000)
    }

    if !skipped.isEmpty {
        print("warning: \(skipped.count) character(s) not producible on this layout, skipped: \(String(skipped))")
    }
}

// MARK: - Focus

/// Prototype of what FocusRestore has to do in phase 1d: bring an app forward and do
/// not type until it has actually taken over.
@discardableResult
func activateAndWait(bundleID: String, timeout: TimeInterval = 5) -> Bool {
    if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            print("error: no app with bundle id \(bundleID)")
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return true }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return false
}

// MARK: - Run

if listLayouts {
    printAvailableLayouts()
    exit(0)
}

let mappingLayoutName = resolveLayout(sourceID: layoutSourceID)?.name
    ?? "UNRESOLVED (\(layoutSourceID ?? "active"))"

if dumpMap {
    let map = buildKeyMap()
    print("mapping against: \(mappingLayoutName)")
    print("reachable characters: \(map.count)")
    var missing: [Character] = []
    for character in text where character != " " {
        switch map[character] {
        case .direct(let code, let flags):
            print(String(format: "  %@  key %3d %@", String(character), Int(code), describe(flags)))
        case .composed(let dead, let deadFlags, let base, let baseFlags):
            print(String(format: "  %@  key %3d %@ then key %3d %@  (dead-key composition)",
                         String(character), Int(dead), describe(deadFlags), Int(base), describe(baseFlags)))
        case nil:
            missing.append(character)
        }
    }
    if !missing.isEmpty { print("NOT producible: \(String(missing))") }
    exit(0)
}

func describe(_ flags: CGEventFlags) -> String {
    var parts: [String] = []
    if flags.contains(.maskShift) { parts.append("shift") }
    if flags.contains(.maskAlternate) { parts.append("option") }
    return parts.isEmpty ? "-" : parts.joined(separator: "+")
}

guard AXIsProcessTrusted() else {
    print("""
    error: no Accessibility permission.

    CGEvent.post silently does nothing without it. The grant belongs to whatever
    launched this binary — usually Terminal.app. Add it under
    System Settings > Privacy & Security > Accessibility, then run again.
    """)
    exit(1)
}

print("mode: \(mode)   delay: \(delayMs)ms   mod-delay: \(modDelayMs)ms")
print("mapping against: \(mappingLayoutName)   (Mac is on \(currentLayoutName()))")
print("text: \(text)")
print("")

if let bundleID = activateBundleID {
    if activateAndWait(bundleID: bundleID) {
        print("activated \(bundleID)")
        usleep(400_000) // let the app settle its own focus before typing
    } else {
        print("error: \(bundleID) never became frontmost")
        exit(1)
    }
} else {
    print("Click into the target field now.")
    for remaining in stride(from: Int(waitSec), to: 0, by: -1) {
        print("  \(remaining)...")
        usleep(1_000_000)
    }
}

print("typing")
let eventSource = CGEventSource(stateID: .hidSystemState)
if mode == "unicode" {
    typeUnicode(text, source: eventSource)
} else {
    typeVirtualKeys(text, source: eventSource)
}
print("done")
