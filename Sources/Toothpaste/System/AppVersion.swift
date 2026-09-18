import Foundation

/// What this build is, for when someone else is running it.
///
/// Everyone builds their own copy from whatever they last pulled, so a version number
/// alone does not identify a build. The commit does, and `scripts/bundle.sh` stamps it
/// in. A `+local` suffix means the working tree had uncommitted changes.
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var commit: String {
        Bundle.main.infoDictionary?["ToothpasteCommit"] as? String ?? "unknown"
    }

    /// Where this copy was built from, stamped alongside the commit. `nil` for a bundle
    /// assembled before the stamp existed, or by something other than `bundle.sh` — in
    /// which case updating from inside the app has nothing to work with. See `Updater`.
    static var source: String? {
        Bundle.main.infoDictionary?["ToothpasteSource"] as? String
    }

    /// e.g. "1.0.0 (57aec6b)" — short enough for a settings row, specific enough to
    /// reproduce someone's build.
    static var display: String { "\(short) (\(commit))" }
}
