import AppKit
import Carbon.HIToolbox

/// Types text as synthetic keystrokes.
///
/// The design here is the result of measurement, not preference — see PLAN.md
/// section 3. In short: virtual keycodes are the primary path because RDP clients
/// ignore unicode payloads entirely, modifiers must be posted as real key events
/// because those clients read modifier state from them, and dead keys must be
/// composed because the common punctuation has no direct key on some layouts.
@MainActor
final class TypingEngine: ObservableObject {
    struct Result {
        var typed = 0
        var skipped: [Character] = []
        var cancelled = false
    }

    @Published private(set) var isTyping = false

    /// Set from outside while typing is in flight. Esc is the panic button; mouse
    /// movement used to be, but that fired constantly during normal use.
    private var cancelRequested = false

    func requestCancel() { cancelRequested = true }

    private var layoutCache: [String: KeyboardLayout] = [:]

    func layout(for profile: TargetProfile) -> KeyboardLayout? {
        let key = "\(profile.layoutSourceID ?? "active")|\(profile.allowOption)"
        if let cached = layoutCache[key] { return cached }
        guard let built = KeyboardLayout.build(
            sourceID: profile.layoutSourceID, allowOption: profile.allowOption
        ) else { return nil }
        layoutCache[key] = built
        return built
    }

    /// Discards cached layouts. Call when the active input source changes.
    func invalidateLayouts() { layoutCache.removeAll() }

    @discardableResult
    func type(_ text: String, using profile: TargetProfile) async -> Result {
        var result = Result()
        guard Accessibility.isTrustedNow, !text.isEmpty else { return result }
        guard let layout = layout(for: profile) else { return result }

        isTyping = true
        defer { isTyping = false }

        // Modifiers held from the hotkey would ride along and corrupt everything.
        await waitForModifiersRelease()

        // Then let the target window settle. Without this the first character is
        // regularly swallowed, because the window has focus but is not yet taking
        // keyboard input.
        if profile.initialDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(Int(profile.initialDelayMs)))
        }

        let source = CGEventSource(stateID: .hidSystemState)
        cancelRequested = false

        for character in text {
            if cancelRequested {
                result.cancelled = true
                break
            }

            if character == "\n" {
                // Newlines need a real Return; a unicode payload does not reliably
                // produce one.
                await press(CGKeyCode(kVK_Return), flags: [], source: source, profile: profile)
                result.typed += 1
            } else {
                switch layout[character] {
                case .direct(let code, let flags):
                    await press(code, flags: flags, source: source, profile: profile)
                    result.typed += 1
                case .composed(let deadCode, let deadFlags, let baseCode, let baseFlags):
                    await press(deadCode, flags: deadFlags, source: source, profile: profile)
                    try? await Task.sleep(for: .milliseconds(Int(profile.characterDelayMs)))
                    await press(baseCode, flags: baseFlags, source: source, profile: profile)
                    result.typed += 1
                case nil:
                    if profile.allowUnicodeFallback {
                        postUnicode(character, source: source)
                        result.typed += 1
                    } else {
                        // Over RDP the unicode path types `a`, so guessing is worse
                        // than reporting. A password typed wrongly in silence is
                        // worse than one that visibly came up short.
                        result.skipped.append(character)
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(Int(profile.characterDelayMs)))
        }

        return result
    }

    // MARK: - Posting

    /// Which physical key is down, beside the generic flag that says a Shift or Option
    /// is. A real keyboard always sets both; these are IOKit's `NX_DEVICELSHFTKEYMASK`
    /// and `NX_DEVICELALTKEYMASK`, for the left-hand keys we press.
    private static let leftShiftKey = CGEventFlags(rawValue: 0x02)
    private static let leftOptionKey = CGEventFlags(rawValue: 0x20)

    private func press(
        _ keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?, profile: TargetProfile
    ) async {
        var modifiers: [(CGKeyCode, CGEventFlags)] = []
        if flags.contains(.maskShift) {
            modifiers.append((CGKeyCode(kVK_Shift), [.maskShift, Self.leftShiftKey]))
        }
        if flags.contains(.maskAlternate) {
            modifiers.append((CGKeyCode(kVK_Option), [.maskAlternate, Self.leftOptionKey]))
        }

        // Awaited rather than slept: at 30ms per modifier a long password would
        // otherwise block the main thread for seconds.
        let modifierDelay = Int(profile.modifierDelayMs)
        var held: CGEventFlags = []

        // Real modifier key events, not just flags on the character event. Native Mac
        // apps accept flags alone; RDP clients do not, and `Hello` arrives as `hello`.
        for (code, flag) in modifiers {
            held.formUnion(flag)
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            event?.flags = held
            event?.post(tap: .cghidEventTap)
            if modifierDelay > 0 { try? await Task.sleep(for: .milliseconds(modifierDelay)) }
        }

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            else { continue }
            // The left/right bits in `held`, not only the generic ones in `flags`. Windows
            // App 11.4 re-syncs the modifiers it has sent against every key event, and
            // decides whether left Shift is down from the device bit alone — so without
            // it, it releases the Shift we just pressed, right before the key. `#` then
            // arrives as `3` and `A` as `a`.
            event.flags = flags.union(held)
            event.post(tap: .cghidEventTap)
        }

        for (code, flag) in modifiers.reversed() {
            if modifierDelay > 0 { try? await Task.sleep(for: .milliseconds(modifierDelay)) }
            held.subtract(flag)
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            event?.flags = held
            event?.post(tap: .cghidEventTap)
        }
    }

    private func postUnicode(_ character: Character, source: CGEventSource?) {
        var utf16 = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        down.flags = []
        up.flags = []
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func waitForModifiersRelease(timeout: TimeInterval = 1.5) async {
        let watched: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSEvent.modifierFlags.intersection(watched).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}
