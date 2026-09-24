import SwiftUI

/// A failed update, reported on the launch that followed it.
///
/// A failed update brings the old version back, and that looks exactly like a successful
/// one: either way the app quietly reappears. This window is what tells them apart. A note
/// in the settings window alone had gone unread, because nobody had a reason to open it.
///
/// A successful update opens nothing. Its release notes were read in the Updates tab just
/// before, the arrow on the menu bar icon is gone afterwards, and the tab still shows what
/// changed since the old version. A window repeating that was one more thing to close.
struct UpdateFailedView: View {
    /// Passed in rather than read from `updater`: dismissing clears it there, and the
    /// window should not go blank in the moment before it closes.
    let failure: String
    @ObservedObject var updater: Updater
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 460, height: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The update did not finish", systemImage: "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("Nothing was replaced, and this is the version you were already running.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var content: some View {
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
