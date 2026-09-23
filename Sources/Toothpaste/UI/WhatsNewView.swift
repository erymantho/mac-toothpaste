import SwiftUI

/// What an update actually did, reported on the launch that followed it.
///
/// An update ends with the app quietly reappearing, which looks exactly like a restart.
/// That is a thin ending for a button whose whole promise is that it replaced the
/// program you were running, and it is a worse one for a failure — which until now left
/// a note in the settings window that nobody had a reason to open.
///
/// Both outcomes land here, in one window, because the question is the same in both
/// cases: did the thing I pressed work?
struct WhatsNewView: View {
    @ObservedObject var updater: Updater
    var onDone: () -> Void

    private var failure: String? { updater.previousFailure }
    private var hasNotes: Bool { !ReleaseNotesList.readable(updater.installedReleases ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 460, height: 400)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if failure != nil {
                Label("The update did not finish", systemImage: "exclamationmark.triangle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                Text("Nothing was replaced, and this is the version you were already running.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Toothpaste \(AppVersion.short)")
                    .font(.title3.weight(.semibold))
                Text(updater.updatedFromVersion.map { "Updated from \($0)." }
                     ?? (updater.justUpdatedFrom != nil ? "Updated." : "Up to date."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            VStack(alignment: .leading, spacing: 12) {
                Text(failure)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The build log from the attempt has the rest of it. Updating by hand still works: git pull and make install in your checkout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show log") { updater.revealLog() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        } else if updater.installedReleases == nil {
            // Still reading the tags. Saying "no notes" here and replacing it a moment later
            // reads as a mistake being corrected.
            ProgressView()
                .controlSize(.small)
                .padding(20)
        } else if !hasNotes {
            // Either the checkout is gone or this version was never tagged. Worth saying
            // rather than showing an empty panel that looks like a failed load.
            Text("No release notes were recorded for this version.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(20)
        } else {
            ScrollView {
                ReleaseNotesList(releases: updater.installedReleases ?? [], named: AppVersion.short)
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            // The commit, not just the version: with clone-and-build everyone sits on
            // whatever they last pulled, so this is the line that identifies a build.
            Text(AppVersion.display)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}
