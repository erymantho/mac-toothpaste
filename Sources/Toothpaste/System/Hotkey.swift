import AppKit
import Carbon.HIToolbox

private var hotkeyHandlers: [UInt32: () -> Void] = [:]
private var nextHotkeyID: UInt32 = 1
private var hotkeyEventHandlerInstalled = false

private func installHotkeyEventHandler() {
    guard !hotkeyEventHandlerInstalled else { return }
    hotkeyEventHandlerInstalled = true

    var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, _ -> OSStatus in
            var identifier = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            if let handler = hotkeyHandlers[identifier.id] {
                DispatchQueue.main.async(execute: handler)
            }
            return noErr
        },
        1, &spec, nil, nil
    )
}

/// A global hotkey, registered through Carbon.
///
/// Deliberately not `NSEvent.addGlobalMonitorForEvents`: that requires Accessibility
/// permission — which we may not have yet, and the panel has to be reachable in order
/// to explain that — and it cannot consume the keystroke, so the shortcut would also
/// reach whatever app is in front.
///
/// Note ⌃Space is unavailable on macOS; it switches input sources. The Windows
/// original's default cannot be reused.
final class Hotkey {
    static let defaultKeyCode = UInt32(kVK_ANSI_V)
    static let defaultModifiers = UInt32(controlKey | optionKey) // ⌃⌥V

    private var reference: EventHotKeyRef?
    private let identifier: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHotkeyEventHandler()

        identifier = nextHotkeyID
        nextHotkeyID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x54505354), id: identifier) // 'TPST'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }

        reference = ref
        hotkeyHandlers[identifier] = handler
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        hotkeyHandlers[identifier] = nil
    }
}
