import Combine
import Foundation

/// App-wide preferences that are not part of a typing profile.
@MainActor
final class Settings: ObservableObject {
    @Published var maxHistory: Int {
        didSet { UserDefaults.standard.set(maxHistory, forKey: Self.maxHistoryKey) }
    }

    /// Hours after which an unpinned entry is forgotten. 0 means never.
    ///
    /// Defaults to never on purpose: switching this on retroactively deletes whatever
    /// is already stored, and nothing destructive should arrive switched on.
    @Published var retentionHours: Int {
        didSet { UserDefaults.standard.set(retentionHours, forKey: Self.retentionKey) }
    }

    /// Whether dragging an entry out of the panel clicks where it is dropped and types
    /// there.
    ///
    /// On by default since 2026-09-23; it started as an opt-in. What that costs is still
    /// true and is said up front in the README: every other thing this app posts is a key
    /// event, and with this on it also posts a mouse click, which makes it an autoclicker
    /// as well as an autotyper and changes what has to be said about it on a managed
    /// machine. It also adds a failure the arm-and-click flow does not have: release over
    /// something that is not a text field and that is what gets clicked.
    @Published var dragToType: Bool {
        didSet { UserDefaults.standard.set(dragToType, forKey: Self.dragToTypeKey) }
    }

    /// Whether entries a password manager marked secret are shown as dots.
    ///
    /// On by default, and the default is the point: a secret should not appear on screen
    /// because nobody got round to deciding. Switching it off is a real choice with a
    /// real consequence, so the settings window says what it is.
    ///
    /// This governs display only. Concealed entries are never written to disk either
    /// way — that rule lives in `HistoryStore` and is deliberately not reachable from
    /// here, because masking is a curtain and persistence is the actual secret-keeping.
    @Published var maskConcealed: Bool {
        didSet { UserDefaults.standard.set(maskConcealed, forKey: Self.maskConcealedKey) }
    }

    /// Whether to ask the checkout's own remote for new version tags at launch.
    ///
    /// This is the only thing the app does over the network at all, which is why it gets
    /// a switch rather than being assumed. Nothing about the user or the clipboard is
    /// sent — it is `git fetch --tags` against whatever remote their clone already has.
    @Published var checkForUpdates: Bool {
        didSet { UserDefaults.standard.set(checkForUpdates, forKey: Self.checkForUpdatesKey) }
    }

    /// Follows the system unless told otherwise. See `AppAppearance`.
    ///
    /// Applied here so that changing it takes effect wherever it is changed from, but
    /// *not* from `init`: this object is built as a stored property of the app delegate,
    /// and whether `NSApp` exists that early depends on the order of two lines in
    /// `main.swift` that have nothing to do with settings. The delegate applies the
    /// stored choice at launch instead, where the application definitely exists.
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            appearance.apply()
        }
    }

    @Published var hotkey: KeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(hotkey) else { return }
            UserDefaults.standard.set(data, forKey: Self.hotkeyKey)
        }
    }

    private static let hotkeyKey = "hotkey"
    private static let appearanceKey = "appearance"
    private static let checkForUpdatesKey = "checkForUpdates"
    private static let maskConcealedKey = "maskConcealed"
    private static let dragToTypeKey = "dragToType"
    private static let maxHistoryKey = "maxHistory"
    private static let retentionKey = "retentionHours"
    static let historyChoices = [10, 25, 50, 75]
    static let retentionChoices = [0, 1, 4, 8, 24, 168]

    static func retentionLabel(_ hours: Int) -> String {
        switch hours {
        case 0: return "Never"
        case 1: return "1 hour"
        case 168: return "1 week"
        case 24: return "1 day"
        default: return "\(hours) hours"
        }
    }

    /// The store's cap, kept as a separate name so the intent reads clearly at the
    /// call site in AppDelegate.
    var maxItemsForStore: Int { maxHistory }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Self.maxHistoryKey)
        maxHistory = Self.historyChoices.contains(stored) ? stored : 50
        retentionHours = UserDefaults.standard.integer(forKey: Self.retentionKey)
        hotkey = UserDefaults.standard.data(forKey: Self.hotkeyKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .fallback
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        // These three default to on, and `object(forKey:)` rather than `bool(forKey:)`
        // because the latter cannot tell "switched off" from "never set". For `dragToType`
        // that is also what carries existing installs across: the value is stored only once
        // someone flips the switch, so a copy that never did takes the new default, and one
        // that switched it off stays off.
        checkForUpdates = UserDefaults.standard.object(forKey: Self.checkForUpdatesKey) as? Bool ?? true
        maskConcealed = UserDefaults.standard.object(forKey: Self.maskConcealedKey) as? Bool ?? true
        dragToType = UserDefaults.standard.object(forKey: Self.dragToTypeKey) as? Bool ?? true
    }
}
