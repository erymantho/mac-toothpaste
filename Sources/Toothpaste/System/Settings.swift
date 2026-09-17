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
    }
}
