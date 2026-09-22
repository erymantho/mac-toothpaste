import Foundation

/// How to type into one kind of destination.
///
/// This is not a global preference and cannot be: local Mac apps and remote sessions
/// want opposite settings. A Mac app wants the active layout, Option combinations and
/// a unicode fallback; a Windows RDP session wants US scancodes, no Option, no
/// fallback, and far slower pacing. See PLAN.md section 3.
struct TargetProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String

    /// Input-source id to map against; nil means the Mac's active layout. For a
    /// remote session this must be the *remote machine's* layout.
    var layoutSourceID: String?

    /// Include Option combinations. False for Windows targets.
    var allowOption: Bool

    /// Fall back to unicode events for characters the layout cannot produce. Must be
    /// false for remote targets: over RDP the fallback silently types `a`, because
    /// the virtual key 0 it pairs with the payload is `kVK_ANSI_A`.
    var allowUnicodeFallback: Bool

    /// Waited once before the first character. A window that has only just been
    /// clicked is not always ready to receive input yet, and the character that gets
    /// lost is the *first* one — which in a password is as bad as any other.
    ///
    /// For a remote session it is doing more than that: the click that chose the
    /// destination still has to travel to the far side and be acted on there before the
    /// remote caret lands in the field. Set too low, everything types correctly into
    /// whatever had focus a moment ago. That is why it is per profile and why the
    /// remote default is several times the local one — and why the right value depends
    /// on someone's actual latency, not on a number chosen here.
    var initialDelayMs: UInt32

    var characterDelayMs: UInt32
    var modifierDelayMs: UInt32

    /// Apps this profile applies to. Empty means "the default for everything else".
    var bundleIdentifiers: [String]

    static let local = TargetProfile(
        id: "local",
        name: "Mac apps",
        layoutSourceID: nil,
        allowOption: true,
        allowUnicodeFallback: true,
        initialDelayMs: 50,
        characterDelayMs: 8,
        modifierDelayMs: 0,
        bundleIdentifiers: []
    )

    static let windowsRemote = TargetProfile(
        id: "windows-remote",
        name: "Windows via RDP",
        layoutSourceID: "com.apple.keylayout.US",
        allowOption: false,
        allowUnicodeFallback: false,
        // A remote session has a window to activate and a network round trip on top,
        // so it needs noticeably longer to be ready than a local app.
        initialDelayMs: 200,
        characterDelayMs: 20,
        modifierDelayMs: 30,
        bundleIdentifiers: [
            "com.microsoft.rdc.macos",             // Windows App
            "com.devolutions.remotedesktopmanager",
            "com.omnissa.horizon.client.mac",
            "com.vmware.fusion",
        ]
    )

    static let builtIns: [TargetProfile] = [.local, .windowsRemote]
}
