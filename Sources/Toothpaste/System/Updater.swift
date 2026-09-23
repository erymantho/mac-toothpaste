import AppKit
import Combine
import Foundation

/// Pulling a new version and restarting into it, from inside the app.
///
/// This is only possible because of how the app is distributed. Everyone already has the
/// checkout and the toolchain that produced their copy, so an update is `git pull` plus
/// the same `make install` they ran the first time — there is nothing to download, and
/// nothing that could be notarised if there were. It also means the button runs whatever
/// is in the repository, which the confirmation says out loud rather than implies.
///
/// The checkout is the one hard dependency. `scripts/bundle.sh` stamps its path into the
/// bundle beside the commit; when it has moved or gone there is no update path at all,
/// and that is its own state rather than something discovered halfway through.
@MainActor
final class Updater: ObservableObject {

    /// One version's release notes, as its tag carries them — kept exactly as git returns
    /// the annotation. Splitting it into sections needs the original line breaks, and
    /// reflowing first would glue a label onto the paragraph above it; `ReleaseNotes` does
    /// both, in that order.
    struct Release: Equatable {
        let version: String
        let annotation: String
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        /// `version` is the newest; `releases` is every version newer than the running one,
        /// newest first. Not only the newest, because a skipped release is still one whose
        /// features the user has not been told about.
        case available(version: String, releases: [Release])
        /// The recorded checkout is gone. Carries the path that was recorded, because
        /// seeing it is usually enough to remember what happened to it.
        case noCheckout(recorded: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Left behind by `scripts/update.sh` when an attempt failed. It has to survive a
    /// restart: by the time it is written this app is gone, so the next launch is the
    /// only place a failure can be reported.
    ///
    /// Consumed on that launch like the success marker. It used to stay until dismissed,
    /// which meant closing the report with the window's close button instead of *Done*
    /// brought it back on every launch after. The reason stays in memory for the session,
    /// so the Updates tab can still show it.
    @Published private(set) var previousFailure: String?

    /// The version this launch replaced, when the launch was one `scripts/update.sh`
    /// triggered. Read once and the marker removed, because the report it drives belongs
    /// to that launch and no other.
    ///
    /// Without this an update finishes by the app quietly reappearing, which is
    /// indistinguishable from it having been restarted for any other reason — and the one
    /// thing someone wants after pressing an update button is to know it worked.
    @Published private(set) var justUpdatedFrom: String?

    /// `justUpdatedFrom` when it is an actual version number. The marker can hold anything
    /// an older `update.sh` wrote — "unknown", or PlistBuddy's own error text when the
    /// installed copy was not where it expected — and that must not end up in a sentence.
    var updatedFromVersion: String? { justUpdatedFrom.flatMap { Self.isVersion($0) ? $0 : nil } }

    /// What this copy is running, as release notes: the tag matching its own version, and
    /// after an update every version the update stepped over as well, newest first. The same
    /// text that was offered before the update, now as what was actually received — and
    /// shown in the Updates tab whenever no newer version is on offer, so a report closed too
    /// quickly is not gone.
    ///
    /// `nil` until the tags have been read, which is not the same as "none": the report after
    /// an update used to open saying no notes were recorded and then fill in a moment later.
    @Published private(set) var installedReleases: [Release]?

    /// Set by the app delegate. Returns a reason when an update must not happen yet —
    /// quitting mid-keystroke would leave half a password in someone's remote session,
    /// and the window between opening settings and clicking the button is small but not
    /// closed.
    var blockedReason: (() -> String?)?

    var updateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    var availableVersion: String? {
        if case let .available(version, _) = status { return version }
        return nil
    }

    init() {
        // A failure is only this launch's to report if it happened after this build was
        // made. A failed update relaunches the old binary, which is older than the marker;
        // a marker from an earlier failure, followed by a successful update by hand, is
        // older than the new binary. 1.2.x never removed its marker until someone pressed
        // Dismiss, so one left over from then would otherwise open as a failure straight
        // after an update that worked.
        let built = Self.buildDate
        if Self.date(of: Self.failureMarker) ?? .distantPast > built {
            previousFailure = try? String(contentsOf: Self.failureMarker, encoding: .utf8)
        }
        try? FileManager.default.removeItem(at: Self.failureMarker)

        // The success marker is the mirror image. `update.sh` writes it before the build, so
        // the binary an update produces is always newer than its marker. A binary that is
        // older is not that update's product — an old copy opened while the build was still
        // running, or the same copy after an update that was cut off — and must leave the
        // marker for the launch it belongs to. Read by the wrong one, it reported an update
        // that had not happened, and the new version then started without a word.
        if let written = Self.date(of: Self.successMarker), written < built {
            justUpdatedFrom = try? String(contentsOf: Self.successMarker, encoding: .utf8)
            try? FileManager.default.removeItem(at: Self.successMarker)
        }
    }

    /// When this binary was built: `bundle.sh` copies it with `cp` and signs it, and
    /// `install.sh` installs it with `ditto`, which keeps the date.
    private static var buildDate: Date {
        Bundle.main.executableURL.flatMap { date(of: $0) } ?? .distantPast
    }

    private static func date(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Read from the checkout rather than carried through the update, so the notes are
    /// whatever the tags actually say now. Local only — `git tag` reads what the last fetch
    /// brought in, so this costs no network access. Silent when there is no checkout or no
    /// tag for this version: the report is still worth showing without them.
    func loadInstalledReleases() {
        guard installedReleases == nil else { return }
        guard let checkout = Self.checkout else {
            installedReleases = []
            return
        }
        let current = AppVersion.short
        // `update.sh` writes "unknown" when it could not read the old version, and treating
        // that as 0 would pull in every tag ever made. An update that did not raise the
        // version at all — a newer commit on the same number — would otherwise select an
        // empty range and report that there are no notes, so it counts as no range either.
        let since = updatedFromVersion.flatMap { Self.isNewer(current, than: $0) ? $0 : nil }
        Task.detached(priority: .utility) {
            let tags = Self.versionTags(in: checkout) ?? []
            let releases = Self.releases(from: tags, in: checkout) { version in
                guard !Self.isNewer(version, than: current) else { return false }
                // By value, like every other comparison here: a `v1.3` tag is the 1.3.0 build.
                guard let since else { return Self.isSame(version, current) }
                return Self.isNewer(version, than: since)
            }
            await MainActor.run { self.installedReleases = releases }
        }
    }

    // MARK: - Checking

    func check() {
        guard status != .checking else { return }
        guard let checkout = Self.checkout else {
            status = .noCheckout(recorded: AppVersion.source ?? "")
            return
        }

        status = .checking
        let current = AppVersion.short
        Task.detached(priority: .utility) {
            let result = Self.probe(checkout: checkout, current: current)
            await MainActor.run { self.status = result }
        }
    }

    private nonisolated static func probe(checkout: String, current: String) -> Status {
        // Only refs move here: remote-tracking branches and tags. The working tree and
        // the current branch are untouched, which is what makes this safe to run on a
        // timer over somebody's repository.
        //
        // `--force` because a tag that was moved or re-created on the remote is otherwise
        // refused ("would clobber existing tag") and the whole fetch exits 1 — silently, under
        // `--quiet` — on every check from then on, for every clone that had the old one. No
        // update would ever be offered again. A clone mirrors the remote's tags; it has no
        // business keeping its own version of one.
        let fetched = git(["fetch", "--tags", "--force", "--quiet", "origin"], in: checkout, timeout: 25)
        guard fetched.ok else {
            return .failed(fetched.error.isEmpty ? "git fetch failed" : fetched.error)
        }

        guard let tags = versionTags(in: checkout), !tags.isEmpty else {
            return .failed("the repository has no version tags")
        }

        let newer = releases(from: tags, in: checkout) { isNewer($0, than: current) }
        guard let newest = newer.first else { return .upToDate }
        return .available(version: newest.version, releases: newer)
    }

    /// Every version tag in the checkout, newest first, one per version.
    ///
    /// Sorted here by the parsed number rather than trusted to `--sort=-v:refname`, which
    /// compares the raw names: a tag written without the `v` sorts below every tag with one,
    /// so `1.5.0` came out older than `v1.4.0` and the wrong version was offered as newest.
    /// Two spellings of one version — `v2` and `v2.0` — keep only one: an annotated tag
    /// before a lightweight one, since only an annotated tag carries notes, and then the `v`
    /// spelling. Chosen by name alone, a lightweight `v1.3.0` hid an annotated `1.3.0`.
    private nonisolated static func versionTags(in checkout: String) -> [(tag: String, version: String)]? {
        // Tag names cannot contain spaces, so splitting at the first one is safe.
        let listed = git(["tag", "--list", "--format=%(objecttype) %(refname:short)"],
                         in: checkout, timeout: 10)
        guard listed.ok else { return nil }
        let candidates = listed.output
            .split(separator: "\n")
            .compactMap { line -> (tag: String, version: String, annotated: Bool)? in
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let tag = String(parts[1])
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                return isVersion(version) ? (tag, version, parts[0] == "tag") : nil
            }
            .sorted { a, b in
                a.annotated != b.annotated ? a.annotated : (a.tag.hasPrefix("v") && !b.tag.hasPrefix("v"))
            }
        var kept: [(tag: String, version: String)] = []
        for candidate in candidates where !kept.contains(where: { isSame($0.version, candidate.version) }) {
            kept.append((candidate.tag, candidate.version))
        }
        return kept.sorted { isNewer($0.version, than: $1.version) }
    }

    /// The annotations of the tags whose version passes `include`, newest first.
    ///
    /// `%(contents)` is the tag's annotation, which is where this project writes its release
    /// notes — but for a lightweight tag it is the message of the commit the tag points at,
    /// trailers included. The format asks for the contents only when the object is a tag,
    /// so a lightweight tag reads as empty and is left out. One call per tag: there are a
    /// handful, the reads are local, and a single call would need a delimiter that no
    /// annotation could ever contain.
    private nonisolated static func releases(
        from tags: [(tag: String, version: String)], in checkout: String,
        including include: (String) -> Bool
    ) -> [Release] {
        tags
            .filter { include($0.version) }
            .map { tag in
                let format = "--format=%(if:equals=tag)%(objecttype)%(then)%(contents)%(end)"
                let result = git(["tag", "--list", format, tag.tag], in: checkout, timeout: 10)
                return Release(version: tag.version, annotation: result.ok ? result.output : "")
            }
    }

    private nonisolated static func isSame(_ a: String, _ b: String) -> Bool {
        !isNewer(a, than: b) && !isNewer(b, than: a)
    }

    /// Only plain dotted numbers count as versions. A stray tag that happens to exist in a
    /// clone — a test tag, a fork's own naming — would otherwise compare as 0 and slip in.
    private nonisolated static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Compares `1.2.10` against `1.2.9` component by component. Comparing the strings
    /// gets exactly that pair wrong, and a version check that offers a downgrade is
    /// worse than no version check.
    private nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Updating

    /// Hands the rest to `scripts/update.sh` and quits.
    ///
    /// The app cannot supervise its own replacement — `install.sh` quits it before it
    /// copies, so whatever was watching would be the thing being replaced. The helper is
    /// spawned detached and reparented to launchd the moment this process goes.
    func update() {
        if let reason = blockedReason?() {
            status = .failed(reason)
            return
        }
        guard let checkout = Self.checkout else {
            status = .noCheckout(recorded: AppVersion.source ?? "")
            return
        }

        let helper = checkout + "/scripts/update.sh"
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            status = .failed("scripts/update.sh is missing from \(checkout)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper, String(ProcessInfo.processInfo.processIdentifier), checkout]
        do {
            try process.run()
        } catch {
            status = .failed("could not start the updater: \(error.localizedDescription)")
            return
        }

        // The helper waits for this pid to disappear before it touches anything, so the
        // only thing that matters here is that it has started.
        NSApp.terminate(nil)
    }

    func dismissFailure() {
        try? FileManager.default.removeItem(at: Self.failureMarker)
        previousFailure = nil
    }

    /// The marker says what went wrong in one line; the log has the build output that
    /// explains it. Reveal rather than open, because the useful thing is often the
    /// hundred lines above the error.
    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.log])
    }

    // MARK: - Where things are

    /// The recorded checkout, but only if it still looks like one.
    private nonisolated static var checkout: String? {
        guard let path = AppVersion.source else { return nil }
        let manager = FileManager.default
        guard manager.fileExists(atPath: path + "/.git"),
              manager.fileExists(atPath: path + "/Makefile")
        else { return nil }
        return path
    }

    private nonisolated static var supportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.michaelsmith.toothpaste", isDirectory: true)
    }

    private nonisolated static var failureMarker: URL {
        supportDirectory.appendingPathComponent("update-failed")
    }

    private nonisolated static var successMarker: URL {
        supportDirectory.appendingPathComponent("update-succeeded")
    }

    nonisolated static var log: URL {
        supportDirectory.appendingPathComponent("update.log")
    }

    // MARK: - git

    private struct GitResult {
        let output: String
        let error: String
        let ok: Bool
    }

    private nonisolated static func git(
        _ arguments: [String], in directory: String, timeout: TimeInterval
    ) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments

        // Without these, a repository that wants credentials blocks forever on a prompt
        // that has no terminal to appear in, and the check simply never returns.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["SSH_ASKPASS_REQUIRE"] = "never"
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return GitResult(output: "", error: error.localizedDescription, ok: false)
        }

        // A hung fetch is the likely failure behind a corporate proxy, and a spinner
        // that never stops is worse than an error message.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        return GitResult(
            output: String(decoding: outputData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            error: String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            ok: process.terminationStatus == 0
        )
    }
}
