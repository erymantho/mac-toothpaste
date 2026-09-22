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

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String)
        /// The recorded checkout is gone. Carries the path that was recorded, because
        /// seeing it is usually enough to remember what happened to it.
        case noCheckout(recorded: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Left behind by `scripts/update.sh` when an attempt failed. It has to survive a
    /// restart: by the time it is written this app is gone, so the next launch is the
    /// only place a failure can be reported.
    @Published private(set) var previousFailure: String?

    /// The version this launch replaced, when the launch was one `scripts/update.sh`
    /// triggered. Read once and the marker removed, because the report it drives belongs
    /// to that launch and no other.
    ///
    /// Without this an update finishes by the app quietly reappearing, which is
    /// indistinguishable from it having been restarted for any other reason — and the one
    /// thing someone wants after pressing an update button is to know it worked.
    @Published private(set) var justUpdatedFrom: String?

    /// The annotation of the tag matching the running version. The same text that was
    /// shown before the update, now as what was actually received.
    @Published private(set) var releaseNotes = ""

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
        previousFailure = try? String(contentsOf: Self.failureMarker, encoding: .utf8)
        justUpdatedFrom = try? String(contentsOf: Self.successMarker, encoding: .utf8)
        if justUpdatedFrom != nil {
            try? FileManager.default.removeItem(at: Self.successMarker)
        }
    }

    /// Read from the checkout rather than carried through the update, so the notes are
    /// whatever the tag actually says now. Silent when there is no checkout or no tag for
    /// this version: the report is still worth showing without them.
    func loadReleaseNotes() {
        guard let checkout = Self.checkout else { return }
        let tag = "v\(AppVersion.short)"
        Task.detached(priority: .utility) {
            let result = Self.git(["tag", "--list", "--format=%(contents)", tag],
                                  in: checkout, timeout: 10)
            let notes = result.ok ? Self.reflowed(result.output) : ""
            await MainActor.run { self.releaseNotes = notes }
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
        let fetched = git(["fetch", "--tags", "--quiet", "origin"], in: checkout, timeout: 25)
        guard fetched.ok else {
            return .failed(fetched.error.isEmpty ? "could not reach the repository" : fetched.error)
        }

        let listed = git(["tag", "--list", "--sort=-v:refname"], in: checkout, timeout: 10)
        guard listed.ok,
              let newest = listed.output.split(separator: "\n").first.map(String.init)
        else { return .failed("the repository has no version tags") }

        let version = newest.hasPrefix("v") ? String(newest.dropFirst()) : newest
        guard isNewer(version, than: current) else { return .upToDate }

        // `%(contents)` is the tag's annotation, which is where this project's release
        // notes actually live — see the messages on v1.1.0 and v1.1.1.
        let notes = git(["tag", "--list", "--format=%(contents)", newest], in: checkout, timeout: 10)
        return .available(version: version, notes: reflowed(notes.output))
    }

    /// Joins the lines within a paragraph so the view can wrap the text to whatever width
    /// it has.
    ///
    /// Tag annotations are hard-wrapped for a terminal, and re-wrapping an already-wrapped
    /// paragraph to a narrower width leaves a trail of orphans — every line that no longer
    /// fits sheds two or three words onto a line of its own. It reads as broken alignment
    /// rather than as wrapping, which is how it was reported.
    ///
    /// Blank lines keep separating paragraphs, and a line that is indented or starts a
    /// bullet is left where it is: there the break was meant.
    private nonisolated static func reflowed(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { paragraph in
                var lines: [String] = []
                for raw in paragraph.components(separatedBy: "\n") {
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    let deliberate = raw.hasPrefix(" ") || raw.hasPrefix("\t")
                        || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                        || trimmed.hasPrefix("\u{2022} ")

                    if deliberate || lines.isEmpty {
                        lines.append(deliberate ? raw : trimmed)
                    } else {
                        lines[lines.count - 1] += " " + trimmed
                    }
                }
                return lines.joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
