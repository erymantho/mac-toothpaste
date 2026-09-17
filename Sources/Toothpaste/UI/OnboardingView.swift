import SwiftUI

/// Explains the one permission the app cannot work without.
///
/// This exists because the failure is silent. Without the grant `CGEvent.post` returns
/// no error and simply types nothing, so the app looks broken rather than unpermitted.
/// Everything here is aimed at the three things that actually go wrong: not knowing it
/// is needed, granting it to the wrong copy of the app, and not noticing that a grant
/// from an earlier build has gone stale.
struct OnboardingView: View {
    @ObservedObject var accessibility: Accessibility
    var onDone: () -> Void

    private var granted: Bool { accessibility.isTrusted && !Accessibility.debugForceUngranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if granted { grantedBody } else { instructions }
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 460, height: 430)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(granted ? "Toothpaste is ready" : "Toothpaste needs one permission")
                .font(.title3.weight(.semibold))
            Text(granted
                 ? "It types your clipboard as keystrokes, which is why it works where ⌘V does not — remote sessions, VM consoles, password fields."
                 : "It types your clipboard as keystrokes, which macOS treats as controlling your computer. Without the permission it types nothing at all — no error, no warning.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(1, "Open Accessibility settings") {
                Button("Open Privacy & Security → Accessibility") {
                    Accessibility.openSystemSettings()
                }
            }

            step(2, "Switch on Toothpaste in the list") {
                // The grant is tied to one bundle, so it matters which copy is listed.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(Accessibility.bundleLocation)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Show me") { Accessibility.revealInFinder() }
                            .controlSize(.small)
                    }
                    if Accessibility.isRunningFromBuildDirectory {
                        Label(
                            "This is a build copy, deleted and recreated on every build. The permission itself follows the signature and will survive, but launch-at-login points at a path — run `make install` and use the copy in ~/Applications.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            step(3, "That is it") {
                Text("This window notices on its own — no restart needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("waiting for the permission…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(20)
    }

    private var grantedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility permission granted", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.ok)

            VStack(alignment: .leading, spacing: 8) {
                Text("How it works").font(.callout.weight(.semibold))
                bullet("Press ⌃⌥V, or click 📝 in the menu bar.")
                bullet("Pick an item — the panel stays open and the item is armed.")
                bullet("Click the field you want it in. That click chooses the destination, so it works inside a remote session too.")
                bullet("Esc cancels, mid-typing as well.")
            }

            Text("Nothing you copy is written to disk. Pin an item to keep it across restarts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func step<Content: View>(
        _ number: Int, _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout.weight(.medium))
                content()
            }
        }
    }

    private var footer: some View {
        HStack {
            if !granted {
                Text("You can close this — the menu bar item explains it too.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(granted ? "Done" : "Close") { onDone() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
