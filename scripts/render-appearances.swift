import AppKit
import SwiftUI

/// Renders the app's windows offscreen under each appearance choice, so both palettes
/// can be checked without switching the machine over.
///
/// Driven by `scripts/render-appearances.sh`, which supplies the output directory and
/// points `HOME` at a scratch copy — `HistoryStore` saves on a timer and would otherwise
/// write the mock items below over the real `history.json`.
///
/// Two things here are deliberate. The appearance is chosen by assigning to
/// `Settings.appearance`, the path the picker uses, rather than by calling `apply()`;
/// an earlier version did the latter and missed that a `Settings` built afterwards
/// applied the stored choice over the top. And the windows set no appearance of their
/// own, so they can only inherit it from `NSApp` — which is the mechanism being tested.
@main
struct RenderAppearances {
    static func main() {
        // Constructing an `Updater` deletes whatever update markers it finds, and this
        // renderer plants fake ones on purpose. Run against the real support folder that
        // would wipe a real pending report and leave a fake failure behind for the app to
        // show. The script points CFFIXED_USER_HOME at a scratch directory — HOME on its own
        // is not enough, Foundation reads the other first — so refuse to run without it.
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path
        if let real = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }),
           support.hasPrefix(real + "/") {
            FileHandle.standardError.write(Data(
                "refusing to run: \(support) is the real support folder. Use scripts/render-appearances.sh.\n".utf8))
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Held for the lifetime of run(): NSApplication does not retain its delegate.
        let renderer = MainActor.assumeIsolated { Renderer() }
        app.delegate = renderer
        app.run()
    }
}

@MainActor
private final class Renderer: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private let state = PanelState()
    private let profiles = ProfileStore()
    private let settings = Settings()
    private let accessibility = Accessibility()
    private let updater = Updater()
    private let navigation = SettingsNavigation()
    private var outDir = URL(fileURLWithPath: ".")

    func applicationDidFinishLaunching(_ note: Notification) {
        if CommandLine.arguments.count > 1 {
            outDir = URL(fileURLWithPath: CommandLine.arguments[1])
        }
        populate()

        // One turn of the run loop before anything is measured, so AppKit has finished
        // waking up and the first render is not the odd one out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            print("system is set to: \(NSApp.effectiveAppearance.name.rawValue)")
            for choice in AppAppearance.allCases {
                self.settings.appearance = choice
                self.shoot(self.panel, 360, 320, "panel", choice, windowBackground: false)
                self.shoot(self.armedPanel, 360, 320, "panel-armed", choice, windowBackground: false)
                self.shoot(self.preferences(.general), 760, 660, "settings", choice)
                self.shoot(self.preferences(.updates), 760, 660, "settings-updates", choice)
                self.shoot(self.notesInForm(Self.sectionedNotes), 760, 420, "release-notes-tab", choice)
                self.shoot(self.notesInForm(Self.proseNotes), 760, 300, "release-notes-prose", choice)
                self.shoot(self.skippedVersions, 760, 560, "release-notes-skipped", choice)
                self.shoot(self.dragCards, 420, 200, "drag-card", choice)
                self.shoot(self.onboarding, 460, 430, "onboarding", choice)
                self.shoot(self.updateFailed, 460, 300, "update-failed", choice)
            }
            print("\nwritten to \(self.outDir.path)")
            exit(0)
        }
    }

    /// Enough variety that every colour in `Theme` appears at least once: a pinned row,
    /// a concealed one, and the missing-permission warning.
    private func populate() {
        store.add(text: "https://github.com/erymantho/mac-toothpaste", concealed: false)
        store.add(text: "ssh deploy@10.44.2.19 -p 2202", concealed: false)
        store.add(text: "not-a-real-password", concealed: true)
        store.add(text: "SELECT * FROM klanten WHERE actief = true;", concealed: false)
        store.add(text: #"\\fileserver\uitwijk\aks"#, concealed: false)
        if let newest = store.items.first { store.togglePin(newest.id) }
        state.statusLine = "from Microsoft Remote Desktop · profile: RDP"
        state.accessibilityGranted = false
    }

    private var panel: AnyView {
        state.armed = nil
        return AnyView(PanelView(
            store: store, state: state, profiles: profiles, settings: settings,
            onArm: { _ in }, onDrop: { _, _ in }, onOpenSettings: {}, onCopy: { _ in },
            onDisarm: {}, onClose: {}
        ))
    }

    /// The armed banner is accent text on an accent wash, the one place where the two
    /// palettes could plausibly disagree about whether it reads.
    private var armedPanel: AnyView {
        state.armed = store.items.first
        return AnyView(PanelView(
            store: store, state: state, profiles: profiles, settings: settings,
            onArm: { _ in }, onDrop: { _, _ in }, onOpenSettings: {}, onCopy: { _ in },
            onDisarm: {}, onClose: {}
        ))
    }

    private func preferences(_ tab: SettingsTab) -> AnyView {
        navigation.tab = tab
        return AnyView(SettingsView(
            settings: settings, profiles: profiles, store: store,
            accessibility: accessibility, updater: updater, navigation: navigation,
            onHotkeyChange: { _ in nil }
        ))
    }

    /// Release notes cannot be reached through the real window here. The Updates tab reads
    /// them from the tags in the checkout, and a bare binary has no `ToothpasteSource`, so
    /// there is no checkout to read. They are rendered instead inside the container that tab
    /// uses, because the container is what decides the layout: rendered as a bare root, the
    /// view reported an ideal height of several thousand points.
    private func notesInForm(_ annotation: String) -> AnyView {
        AnyView(
            Form {
                Section("What's new in 1.3.0") {
                    ReleaseNotesView(notes: ReleaseNotes(annotation))
                }
            }
            .formStyle(.grouped)
            .padding()
        )
    }

    /// The card carried beside the pointer, over a window background so its shadow and
    /// tilt can be judged: a plain entry, a pinned one, and a masked one — which must show
    /// as dots, never as the secret.
    private var dragCards: AnyView {
        func card(_ text: String, pinned: Bool) -> some View {
            DragPreviewCard(text: text, pinned: pinned, size: DragPreview.measure(text))
                .frame(height: 50)
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                card("ssh deploy@10.44.2.19 -p 2202", pinned: false)
                card(#"\\fileserver\uitwijk\aks"#, pinned: true)
                card(String(repeating: "\u{2022}", count: 16), pinned: false)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    /// Someone two versions behind: both are listed, newest first, so a feature added in the
    /// release they skipped is not lost behind the fixes-only one that followed.
    private var skippedVersions: AnyView {
        AnyView(
            Form {
                Section("What's new since 1.2.1") {
                    ReleaseNotesList(releases: [
                        Updater.Release(version: "1.3.1", annotation: """
                        Fixed:
                        - A fix that shipped on its own, after the feature release.
                        """),
                        Updater.Release(version: "1.3.0", annotation: Self.sectionedNotes),
                    ])
                }
            }
            .formStyle(.grouped)
            .padding()
        )
    }

    /// Written the way a real annotation is: wrapped for git, bullets continued on an
    /// indented line, and labels rather than headings.
    private static let sectionedNotes = """
    Drag-to-type is off until you switch it on in settings.

    New:
    - Drag an entry to a field to click and type there. With it on, Toothpaste
      posts a mouse click as well as keystrokes.
    - Updates have their own tab, and the release notes are split like this.

    Fixed:
    - Clicking a row while another window was in front took two clicks.
    - Text arrived in the field you had selected before, not the one you clicked.
    """

    /// Every tag up to 1.2.1 looks like this: no labels, one block of prose.
    private static let proseNotes = """
    Fixes a panel that could not be moved. macOS 27 stopped letting a SwiftUI
    window be dragged by its background, which is how the panel had always been
    moved, and no setting or restart brought it back.
    """

    private var onboarding: AnyView {
        AnyView(OnboardingView(accessibility: accessibility, onDone: {}))
    }

    /// The window a failed update leaves behind. It is handed its failure directly, so
    /// nothing has to be planted for it; building an `Updater` still consumes whatever
    /// markers the support folder holds, which is safe only because that folder is a
    /// scratch one — see the guard in `main`, which refuses to run otherwise.
    private var updateFailed: AnyView {
        AnyView(UpdateFailedView(failure: "the build failed. See update.log.",
                                 updater: Updater(), onDone: {}))
    }

    /// `windowBackground` stands in for what a real titled window draws behind its content.
    /// `cacheDisplay` captures the content view only, and the window's own background is
    /// drawn outside it — so any window whose SwiftUI content paints no background of its
    /// own came out transparent, which in dark mode means white text on nothing: a blank
    /// image. That was true of the post-update window, then `WhatsNewView`, and of the
    /// onboarding window, unnoticed for as long as only their light renders were being
    /// looked at. The panel is the exception, because it is meant to be transparent around
    /// its rounded corners.
    private func shoot(_ root: AnyView, _ width: CGFloat, _ height: CGFloat,
                       _ name: String, _ choice: AppAppearance, windowBackground: Bool = true) {
        let content = windowBackground
            ? AnyView(root.background(Color(nsColor: .windowBackgroundColor)))
            : root
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)

        // Never ordered front, so nothing appears on screen and no focus is taken.
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host          // no window.appearance: it has to inherit

        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()

        let file = "\(name)-\(choice.rawValue).png"
        let resolved = window.effectiveAppearance.name.rawValue
        print("  \(choice.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0))"
              + "\(file.padding(toLength: 28, withPad: " ", startingAt: 0)) \(resolved)")

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: outDir.appendingPathComponent(file))
    }
}
