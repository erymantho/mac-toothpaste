import AppKit
import Combine

/// Holds the typing profiles and decides which one a destination gets.
///
/// Automatic by default, matching the destination app's bundle identifier, with a
/// manual override for what the list does not cover — a remote session nested inside
/// some other app, say.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [TargetProfile] = [] {
        didSet { persist() }
    }

    /// nil means "decide from the destination app".
    @Published var manualProfileID: String? {
        didSet { UserDefaults.standard.set(manualProfileID, forKey: Self.overrideKey) }
    }

    private static let overrideKey = "manualProfileID"
    private static let profilesKey = "typingProfiles"

    init() {
        manualProfileID = UserDefaults.standard.string(forKey: Self.overrideKey)
        profiles = Self.loadPersisted() ?? TargetProfile.builtIns
    }

    // MARK: - Selection

    func profile(for application: NSRunningApplication?) -> TargetProfile {
        if let manualProfileID,
           let chosen = profiles.first(where: { $0.id == manualProfileID }) {
            return chosen
        }
        guard let bundleID = application?.bundleIdentifier else { return fallback }
        return profiles.first { $0.bundleIdentifiers.contains(bundleID) } ?? fallback
    }

    /// Used when nothing claims the destination. The first profile with no app list is
    /// the catch-all; if the user has deleted that, anything is better than crashing.
    private var fallback: TargetProfile {
        profiles.first { $0.bundleIdentifiers.isEmpty } ?? profiles.first ?? .local
    }

    /// What the panel shows: which profile applies right now, and why.
    func describeSelection(for application: NSRunningApplication?) -> String {
        let chosen = profile(for: application)
        return "\(chosen.name) (\(manualProfileID == nil ? "auto" : "manual"))"
    }

    // MARK: - Editing

    func update(_ profile: TargetProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func add() -> TargetProfile {
        var new = TargetProfile.local
        new.id = UUID().uuidString
        new.name = "New profile"
        new.bundleIdentifiers = []
        profiles.append(new)
        return new
    }

    func remove(_ id: String) {
        profiles.removeAll { $0.id == id }
        if manualProfileID == id { manualProfileID = nil }
    }

    func resetToDefaults() {
        profiles = TargetProfile.builtIns
        manualProfileID = nil
    }

    /// The app a bundle identifier belongs to, for showing a name instead of a
    /// reverse-DNS string in the editor.
    static func displayName(forBundleIdentifier id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesKey)
    }

    private static func loadPersisted() -> [TargetProfile]? {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([TargetProfile].self, from: data),
              !decoded.isEmpty
        else { return nil }
        return decoded
    }
}
