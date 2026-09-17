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
                self.shoot(self.panel, 360, 320, "panel", choice)
                self.shoot(self.armedPanel, 360, 320, "panel-armed", choice)
                self.shoot(self.preferences, 760, 560, "settings", choice)
                self.shoot(self.onboarding, 460, 430, "onboarding", choice)
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
            store: store, state: state, profiles: profiles,
            onArm: { _ in }, onOpenSettings: {}, onCopy: { _ in },
            onDisarm: {}, onClose: {}
        ))
    }

    /// The armed banner is accent text on an accent wash, the one place where the two
    /// palettes could plausibly disagree about whether it reads.
    private var armedPanel: AnyView {
        state.armed = store.items.first
        return AnyView(PanelView(
            store: store, state: state, profiles: profiles,
            onArm: { _ in }, onOpenSettings: {}, onCopy: { _ in },
            onDisarm: {}, onClose: {}
        ))
    }

    private var preferences: AnyView {
        AnyView(SettingsView(
            settings: settings, profiles: profiles, store: store,
            accessibility: accessibility, onHotkeyChange: { _ in nil }
        ))
    }

    private var onboarding: AnyView {
        AnyView(OnboardingView(accessibility: accessibility, onDone: {}))
    }

    private func shoot(_ root: AnyView, _ width: CGFloat, _ height: CGFloat,
                       _ name: String, _ choice: AppAppearance) {
        let host = NSHostingView(rootView: root)
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
