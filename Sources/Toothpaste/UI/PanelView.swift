import SwiftUI

/// Phase 1e: functional, deliberately plain. Styling is deferred by decision.
struct PanelView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var settings: Settings
    var onArm: (ClipItem) -> Void
    var onOpenSettings: () -> Void
    var onCopy: (ClipItem) -> Void
    var onDisarm: () -> Void
    var onClose: () -> Void

    @State private var query = ""
    /// nil until the list is actually used. Highlighting the top row on open made it
    /// look chosen when nothing had been chosen.
    @State private var selection: Int?
    @State private var revealed: Set<ClipItem.ID> = []
    @State private var confirmingClear = false

    /// The search is a plain string this view maintains, not an `NSTextField`.
    ///
    /// Two approaches failed first. Seeding a real field with the intercepted first
    /// keystroke lost that character, because a text field selects its contents when it
    /// takes focus and the next keystroke replaced it — typing "ser" produced "er".
    /// Keeping the field present but zero-height lost *every* keystroke, because a
    /// field with no height will not take focus at all.
    ///
    /// Handling the keys directly costs selection and cursor movement inside the query,
    /// which is a fair trade for something you type three characters into.
    private var searchVisible: Bool { !query.isEmpty }

    private var filtered: [ClipItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Everything below the header refuses to start a window drag, so brushing
            // past a row cannot shift the panel.
            VStack(alignment: .leading, spacing: 0) {
                if state.armed != nil { armedBanner }
                if searchVisible { queryDisplay }
                Theme.separator.frame(height: 1)
                list
                footer
            }
            .background(WindowDragBlocker())
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(state.armed != nil ? Color.accentColor : Theme.border,
                              lineWidth: state.armed != nil ? 2 : 1)
        )
        // Nothing else here is focusable, so the panel itself has to take focus for
        // key presses to arrive at all.
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            selection = nil
            confirmingClear = false
            query = ""
        }
        .onKeyPress { press in
            guard let scalar = press.characters.unicodeScalars.first else { return .ignored }

            // Backspace is handled here rather than through
            // `.onKeyPress(keys: [.delete])`, which never fires: the key arrives at this
            // catch-all as 0x7F and the specific handler is simply not consulted. It
            // also has to be excluded from the printable range below, since 0x7F sits
            // above 0x20 — that is why backspace first appeared to do nothing at all
            // while quietly appending a DEL character to the query.
            if scalar.value == 0x7F {
                guard !query.isEmpty else { return .handled }
                if press.modifiers.contains(.command) { query = "" } else { query.removeLast() }
                return .handled
            }

            // Otherwise only characters someone could be typing: control codes sit below
            // 0x20, arrow and function keys in the private-use range from 0xF700.
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                  scalar.value >= 0x20, scalar.value < 0xF700
            else { return .ignored }
            query.append(contentsOf: press.characters)
            return .handled
        }
        .onKeyPress(.escape) {
            // Esc unwinds one step at a time. Closing the panel straight away would
            // leave you unsure whether anything was cleared, or whether the item you
            // had chosen is still waiting for a destination.
            if confirmingClear {
                confirmingClear = false
            } else if state.armed != nil {
                onDisarm()
            } else if searchVisible {
                query = ""
            } else {
                onClose()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !filtered.isEmpty else { return .handled }
            selection = min((selection ?? -1) + 1, filtered.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !filtered.isEmpty else { return .handled }
            selection = max((selection ?? 1) - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            // With nothing explicitly selected, Return takes the top row — which is
            // what you mean after typing a search.
            let index = selection ?? 0
            if filtered.indices.contains(index) { onArm(filtered[index]) }
            return .handled
        }
    }

    /// The header is the panel's only drag surface, and since macOS 27 that takes a real
    /// `NSView` over the text — see `WindowDragHandle`. The controls are then stacked
    /// above the handle, which keeps them clickable.
    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("TOOTHPASTE").font(.system(size: 13, weight: .bold, design: .monospaced))
                    Spacer()
                    // A hidden copy, purely to reserve the width the real controls need.
                    // Without it the title and a long profile name would overlap, because
                    // a ZStack does not make its layers avoid each other. Hidden views
                    // take part in layout and in nothing else.
                    headerControls.hidden()
                }
                Text(state.statusLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !state.accessibilityGranted {
                    Text("no Accessibility permission — typing will do nothing")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(12)
            .overlay(WindowDragHandle())

            headerControls.padding(12)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 6) {
            profileMenu
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    /// The one setting worth reaching for often. Everything else is set once per
    /// destination and then left alone, so it lives in the settings window.
    private var profileMenu: some View {
        Menu {
            Button(profiles.manualProfileID == nil ? "✓ Automatic" : "Automatic") {
                profiles.manualProfileID = nil
            }
            Divider()
            ForEach(profiles.profiles, id: \.id) { profile in
                Button(profiles.manualProfileID == profile.id ? "✓ \(profile.name)" : profile.name) {
                    profiles.manualProfileID = profile.id
                }
            }
        } label: {
            Text(activeProfileLabel)
                .font(.system(size: 10, design: .monospaced))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
    }

    private var activeProfileLabel: String {
        guard let id = profiles.manualProfileID,
              let chosen = profiles.profiles.first(where: { $0.id == id })
        else { return "auto" }
        return chosen.name
    }

    /// The panel deliberately stays open after a choice: the destination is picked by
    /// clicking it, not assumed from whatever happened to be in front.
    private var armedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "cursorarrow.click").font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("now click the field you want this typed into")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("esc to cancel")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var queryDisplay: some View {
        HStack(spacing: 4) {
            Text(query)
            Rectangle().fill(Color.accentColor).frame(width: 1, height: 12)
            Spacer()
            Text("esc").foregroundStyle(.tertiary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(8)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == selection, isArmed: state.armed?.id == item.id)
                            .id(item.id)
                            // Kept as a fallback for any sliver the catcher does not
                            // cover. Arming twice does the same thing as arming once.
                            .onTapGesture { onArm(item) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: selection) {
                guard let selection, filtered.indices.contains(selection) else { return }
                proxy.scrollTo(filtered[selection].id)
            }
        }
    }

    private func row(_ item: ClipItem, isSelected: Bool, isArmed: Bool) -> some View {
        // Masking off means the dots go, and with them the eye button that undid them.
        let hidden = settings.maskConcealed && item.concealed && !revealed.contains(item.id)
        return ZStack(alignment: .trailing) {
            // The whole row is the click target, and it is caught in AppKit rather than
            // by a tap gesture — see `ClickCatcher`. The buttons' width is reserved by a
            // hidden copy so the catcher can cover everything without swallowing them.
            HStack(spacing: 6) {
                Text(hidden ? String(repeating: "•", count: min(item.characterCount, 20)) : item.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                rowButtons(item, hidden: hidden).hidden()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .overlay(ClickCatcher { onArm(item) })

            // Above the catcher in z-order, which is what keeps them clickable.
            rowButtons(item, hidden: hidden)
                .padding(.horizontal, 8)
        }
        .background(rowFill(isSelected: isSelected, isPinned: item.pinned))
        .overlay(alignment: .leading) {
            // A stripe rather than a tint: pinned and selected can both be true, and
            // they have to stay tellable apart.
            if item.pinned {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isArmed ? Color.accentColor : .clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func rowButtons(_ item: ClipItem, hidden: Bool) -> some View {
        HStack(spacing: 6) {
            iconButton(item.pinned ? "pin.fill" : "pin") { store.togglePin(item.id) }
                .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
            if item.concealed, settings.maskConcealed {
                iconButton(hidden ? "eye" : "eye.slash") {
                    if hidden { revealed.insert(item.id) } else { revealed.remove(item.id) }
                }
            }
            iconButton("doc.on.doc") { onCopy(item) }
            iconButton("xmark") { store.remove(item.id) }
        }
    }

    /// The accent background means "Return acts on this one". Pinning gets a lighter
    /// fill and a stripe instead, so the two never look like the same thing.
    private func rowFill(isSelected: Bool, isPinned: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        return isPinned ? Theme.rowPinned : Theme.row
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    /// The clear button confirms itself: one click arms it, a second clears. No alert,
    /// because a system dialog would activate the app and the panel is deliberately
    /// non-activating — and no second button, because a lone "sure?" is quicker to use
    /// and impossible to mis-click.
    ///
    /// It disarms itself after a few seconds so a forgotten click cannot be completed
    /// by an unrelated one later.
    private var footer: some View {
        HStack {
            Text(":: \(filtered.count)/\(store.items.count) items")
            Spacer()
            Text("⌃⌥V").padding(.trailing, 8)
            Button(confirmingClear ? "sure?" : "clear") {
                if confirmingClear {
                    store.clearUnpinned()
                    confirmingClear = false
                } else {
                    confirmingClear = true
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(confirmingClear ? Color.accentColor : Color.secondary)
            .disabled(store.items.contains { !$0.pinned } == false)
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: confirmingClear) {
            guard confirmingClear else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { confirmingClear = false }
        }
    }

}
