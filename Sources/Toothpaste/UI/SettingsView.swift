import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var store: HistoryStore
    @ObservedObject var accessibility: Accessibility
    var onHotkeyChange: (KeyCombo) -> String?

    var body: some View {
        TabView {
            GeneralTab(
                settings: settings, store: store,
                accessibility: accessibility, onHotkeyChange: onHotkeyChange
            )
                .tabItem { Text("General") }
            ProfilesTab(profiles: profiles)
                .tabItem { Text("Typing profiles") }
            LayoutCheckTab(profiles: profiles)
                .tabItem { Text("Layout check") }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 520, idealHeight: 560)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: HistoryStore
    @ObservedObject var accessibility: Accessibility
    var onHotkeyChange: (KeyCombo) -> String?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
            Picker("Keep at most", selection: $settings.maxHistory) {
                ForEach(Settings.historyChoices, id: \.self) { Text("\($0) items").tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.maxHistory) { store.maxItems = settings.maxHistory }

            Picker("Forget entries after", selection: $settings.retentionHours) {
                ForEach(Settings.retentionChoices, id: \.self) {
                    Text(Settings.retentionLabel($0)).tag($0)
                }
            }
            Text("Applies while the app is running. Nothing unpinned is written to disk in the first place — a restart already leaves only your pinned entries.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle(LaunchAtLogin.description, isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    launchAtLogin = LaunchAtLogin.set(launchAtLogin)
                }

            LabeledContent("Hotkey") {
                HotkeyRecorder(combo: $settings.hotkey, onRecorded: onHotkeyChange)
            }
            Text("Needs ⌘, ⌃ or ⌥. ⌃Space is unavailable — macOS uses it to switch input sources.")
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
            LabeledContent("Accessibility") {
                HStack {
                    Text(accessibility.isTrusted ? "granted" : "missing")
                        .foregroundStyle(accessibility.isTrusted ? Color.secondary : Color.red)
                    Button("Open Settings") { Accessibility.openSystemSettings() }
                }
            }
            Text("Without it, typing silently does nothing at all.")
                .font(.caption).foregroundStyle(.secondary)

            LabeledContent("Version") {
                Text(AppVersion.display)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Profiles

private struct ProfilesTab: View {
    @ObservedObject var profiles: ProfileStore
    @State private var selectedID: String?

    private var selection: String? { selectedID ?? profiles.profiles.first?.id }

    var body: some View {
        HSplitView {
            list
            if let id = selection, profiles.profiles.contains(where: { $0.id == id }) {
                ProfileEditor(profiles: profiles, profileID: id)
            } else {
                Text("No profile selected").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(profiles.profiles, id: \.id, selection: Binding(
                get: { selection }, set: { selectedID = $0 }
            )) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                    Text(profile.bundleIdentifiers.isEmpty
                         ? "everything else"
                         : "\(profile.bundleIdentifiers.count) app(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(profile.id)
            }
            HStack(spacing: 6) {
                Button { selectedID = profiles.add().id } label: { Image(systemName: "plus") }
                    .help("Add a profile")
                Button {
                    if let id = selection { profiles.remove(id); selectedID = nil }
                } label: { Image(systemName: "minus") }
                .disabled(profiles.profiles.count <= 1)
                .help("Remove the selected profile")
                Spacer()
                Button("Reset") { profiles.resetToDefaults(); selectedID = nil }
                    .help("Back to the two built-in profiles")
            }
            .controlSize(.small)
            .padding(8)
        }
        .frame(minWidth: 180, maxWidth: 240)
    }
}

private struct ProfileEditor: View {
    @ObservedObject var profiles: ProfileStore
    let profileID: String
    @State private var layouts: [(id: String, name: String)] = []

    private var profile: Binding<TargetProfile> {
        Binding(
            get: { profiles.profiles.first { $0.id == profileID } ?? .local },
            set: { profiles.update($0) }
        )
    }

    var body: some View {
        ScrollView {
            Form {
                TextField("Name", text: profile.name)

                Section("Keyboard") {
                    Picker("Map against", selection: Binding(
                        get: { profile.wrappedValue.layoutSourceID ?? "" },
                        set: { profile.wrappedValue.layoutSourceID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("This Mac's active layout").tag("")
                        ForEach(layouts, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Text("For a remote session this must be the *remote machine's* layout — it re-maps our scancodes with its own.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Allow Option combinations", isOn: profile.allowOption)
                    Text("Turn off for Windows targets: macOS puts accents on option+key and Windows has no equivalent.")
                        .font(.caption).foregroundStyle(.secondary)

                    Toggle("Fall back to Unicode for unmappable characters", isOn: profile.allowUnicodeFallback)
                    Text("Must be off for remote sessions — there the fallback silently types the letter a.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Timing") {
                    msField("Initial delay", profile.initialDelayMs, range: 0...2000, step: 10)
                    msField("Between characters", profile.characterDelayMs, range: 0...200, step: 1)
                    msField("Around modifiers", profile.modifierDelayMs, range: 0...200, step: 5)
                    Text("Remote sessions need noticeably larger values than local apps — a window to activate and a network round trip on top.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Applies to") {
                    if profile.wrappedValue.bundleIdentifiers.isEmpty {
                        Text("Everything not claimed by another profile.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(profile.wrappedValue.bundleIdentifiers, id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ProfileStore.displayName(forBundleIdentifier: bundleID))
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { remove(bundleID) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add app…") { addApplication() }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .onAppear { if layouts.isEmpty { layouts = KeyboardLayout.installedLayouts() } }
    }

    /// A number field rather than a slider.
    ///
    /// These are values you reproduce and compare — "modifier delay 30 fixed it" — and
    /// a slider can neither set nor show an exact one. The three fields also have
    /// genuinely different useful ranges, so any single slider scale is either
    /// inconsistent between them or too coarse for the one that needs precision.
    private func msField(
        _ label: String, _ value: Binding<UInt32>, range: ClosedRange<Int>, step: Int
    ) -> some View {
        let number = Binding<Int>(
            get: { Int(value.wrappedValue) },
            set: { value.wrappedValue = UInt32(min(max($0, range.lowerBound), range.upperBound)) }
        )
        return LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: number, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 66)
                Text("ms").font(.caption).foregroundStyle(.secondary)
                Stepper("", value: number, in: range, step: step).labelsHidden()
            }
        }
    }

    private func remove(_ bundleID: String) {
        var updated = profile.wrappedValue
        updated.bundleIdentifiers.removeAll { $0 == bundleID }
        profiles.update(updated)
    }

    /// Picking the app is friendlier than asking anyone to type a reverse-DNS string.
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }

        var updated = profile.wrappedValue
        guard !updated.bundleIdentifiers.contains(bundleID) else { return }
        updated.bundleIdentifiers.append(bundleID)
        profiles.update(updated)
    }
}

// MARK: - Layout check

/// Answers the question worth asking before typing a password into a remote machine:
/// which of these characters will simply not arrive?
private struct LayoutCheckTab: View {
    @ObservedObject var profiles: ProfileStore
    @State private var profileID: String = ""
    @State private var sample = #"Hello123 test@example.com "quoted" 'x' é ü € !@#$%^&* {}[]|\ ~end~"#

    /// Built once per layout choice, not per keystroke. Constructing it means several
    /// thousand `UCKeyTranslate` calls, and as a computed property it ran on every
    /// character typed into the sample field.
    @State private var layout: KeyboardLayout?

    private var chosen: TargetProfile? {
        profiles.profiles.first { $0.id == profileID } ?? profiles.profiles.first
    }

    /// Everything that changes what the map contains, as one value to watch.
    private var layoutKey: String {
        guard let chosen else { return "" }
        return "\(chosen.layoutSourceID ?? "active")|\(chosen.allowOption)"
    }

    private func rebuildLayout() {
        guard let chosen else { layout = nil; return }
        layout = KeyboardLayout.build(sourceID: chosen.layoutSourceID, allowOption: chosen.allowOption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Profile", selection: $profileID) {
                ForEach(profiles.profiles, id: \.id) { Text($0.name).tag($0.id) }
            }

            Text("Text to check")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $sample)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .border(Color.secondary.opacity(0.3))

            if let layout {
                let missing = layout.unproducible(in: sample)
                Divider()
                Text("Mapping against **\(layout.name)** — \(layout.reachableCount) characters reachable")
                    .font(.callout)

                if missing.isEmpty {
                    Label("Every character in this text can be typed.", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.ok)
                } else {
                    Label(
                        "\(missing.count) character(s) cannot be typed and would be skipped:",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Theme.warning)
                    Text(String(Array(Set(missing)).sorted()))
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    if chosen?.allowUnicodeFallback == true {
                        Text("This profile allows the Unicode fallback, so these would be attempted anyway — which works locally and produces the letter a over RDP.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("That layout could not be loaded.").foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .onAppear {
            if profileID.isEmpty { profileID = profiles.profiles.first?.id ?? "" }
            rebuildLayout()
        }
        .onChange(of: layoutKey) { rebuildLayout() }
    }
}
