import AppKit
import SwiftUI

/// Phase 1e: functional, deliberately plain. Styling is deferred by decision.
struct PanelView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var state: PanelState
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var settings: Settings
    var onArm: (ClipItem) -> Void
    var onDrop: (ClipItem, NSPoint) -> Void
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
    /// A pinned row whose delete button has been armed but not confirmed.
    ///
    /// Only pinned rows ask. Everything in the panel now acts on the click that brings it
    /// forward, which is what makes it usable while another window has focus — and which
    /// also means a mis-aimed activating click can land on a delete button. An unpinned
    /// entry lost that way was going to vanish on the next restart regardless; a pinned
    /// one is on disk and does not come back, and that is the only case worth a second
    /// click.
    @State private var confirmingRemove: ClipItem.ID?
    /// The row being dragged out of the panel, which fades while it is carried.
    @State private var carried: ClipItem.ID?
    /// The row under the pointer, which is where a click would land.
    @State private var hovered: ClipItem.ID?
    /// The row button under the pointer, by entry and icon, so its whole slot can show
    /// what a click there will hit.
    @State private var hoveredButton: String?

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
            hovered = nil
            hoveredButton = nil
            confirmingClear = false
            confirmingRemove = nil
            query = ""
        }
        .onKeyPress { press in
            // What the key typed, read from the event itself. `press.characters` is the key
            // as if no modifier but Shift applied: ⌥⇧2 arrives there as "@", not "€", and
            // a dead key as its bare accent. The event has the character the layout made,
            // nothing for a dead key, and the composed one on the key that completes it.
            let typed = NSApp.currentEvent.flatMap { $0.type == .keyDown ? $0.characters : nil }
                ?? press.characters
            guard let scalar = typed.unicodeScalars.first else {
                // A dead key, waiting for the key that completes it: nothing to add yet,
                // and nothing to beep about.
                return press.modifiers.isDisjoint(with: [.command, .control]) ? .handled : .ignored
            }

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
            //
            // Option is not a shortcut here but how characters are typed: € on most Mac
            // layouts, and \, | or brackets on German, French, Belgian and Swiss ones.
            // Refusing it made those unsearchable.
            guard press.modifiers.isDisjoint(with: [.command, .control]),
                  scalar.value >= 0x20, scalar.value < 0xF700
            else { return .ignored }
            query.append(contentsOf: typed)
            return .handled
        }
        .onKeyPress(.escape) {
            // Esc unwinds one step at a time. Closing the panel straight away would
            // leave you unsure whether anything was cleared, or whether the item you
            // had chosen is still waiting for a destination.
            if confirmingRemove != nil {
                confirmingRemove = nil
            } else if confirmingClear {
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
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("now click the field you want this typed into")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("esc to cancel")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        // The words are primary, not accent-coloured. The accent is whatever the user picked,
        // and under a yellow one the one instruction that matters most in the whole flow read
        // at 1.56:1. The icon, the wash and the panel's border still carry the accent.
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
            .task(id: confirmingRemove) {
                guard confirmingRemove != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { confirmingRemove = nil }
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
        let shown = hidden ? String(repeating: "•", count: min(item.characterCount, 20)) : item.preview
        // The whole row is the click target, and it is caught in AppKit rather than by a
        // tap gesture — see `ClickCatcher`. The buttons' width is reserved by a hidden copy
        // so the catcher can cover everything without swallowing them.
        return HStack(spacing: 6) {
            Text(shown)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            rowButtons(item, hidden: hidden, live: false).hidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .overlay(ClickCatcher(
            onClick: { onArm(item) },
            onDrop: settings.dragToType ? { onDrop(item, $0) } : nil,
            // Exactly what the row shows, so a masked entry travels as dots.
            dragCard: { (shown, item.pinned) },
            onDragChanged: { carried = $0 ? item.id : nil },
            onHoverChanged: { inside in
                if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
            }
        ))
        // Above the catcher in z-order, which is what keeps them clickable, and an
        // overlay rather than a sibling so the buttons are given the row's full height.
        // Four points from the edge puts the last glyph where it was with eight, now
        // that its slot is wider than the glyph.
        .overlay(alignment: .trailing) {
            rowButtons(item, hidden: hidden, live: true)
                .padding(.trailing, 4)
        }
        .background {
            ZStack(alignment: .leading) {
                rowFill(isSelected: isSelected, isPinned: item.pinned)
                // Lighter than the keyboard selection, which it can sit on top of. Not while
                // an entry is being dragged: the pointer is aiming elsewhere then.
                if hovered == item.id, carried == nil {
                    Color.accentColor.opacity(0.12)
                }
                if let mark = state.typing, mark.itemID == item.id {
                    TypingFill(mark: mark).transition(.opacity)
                }
            }
        }
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
        .opacity(carried == item.id ? 0.4 : 1)
        .animation(.easeOut(duration: 0.12), value: carried)
    }

    /// `live` is false for the copy that only reserves the buttons' width. That copy sits
    /// four points left of the real one, so tracking the pointer over it would light the
    /// wrong slot.
    private func rowButtons(_ item: ClipItem, hidden: Bool, live: Bool) -> some View {
        // No spacing: the slots meet, so there is no gap between two buttons for a click
        // to fall through to the row.
        HStack(spacing: 0) {
            // A pinned secret lasts this session only — secrets are never written to disk —
            // so its pin is grey rather than accented, and says why. It has to show on the
            // row: an entry becomes secret when a copy of the same text arrives, with nobody
            // looking.
            iconButton(item.pinned ? "pin.fill" : "pin", key: "\(item.id)/pin", live: live,
                       colour: item.pinned && !item.concealed ? .accentColor : .secondary) {
                store.togglePin(item.id)
            }
            .help(item.pinned
                  ? (item.concealed ? "Pinned for this session only: secrets are never saved" : "Unpin")
                  : "Pin")
            if item.concealed, settings.maskConcealed {
                iconButton(hidden ? "eye" : "eye.slash", key: "\(item.id)/reveal", live: live) {
                    if hidden { revealed.insert(item.id) } else { revealed.remove(item.id) }
                }
            }
            iconButton("doc.on.doc", key: "\(item.id)/copy", live: live) { onCopy(item) }
            removeButton(item, live: live)
        }
    }

    private func removeButton(_ item: ClipItem, live: Bool) -> some View {
        let confirming = confirmingRemove == item.id
        // A pending confirmation keeps its warning colour under the pointer: that colour
        // is the message, and the pointer is usually still over it when it appears.
        return iconButton(confirming ? "xmark.circle.fill" : "xmark", key: "\(item.id)/remove",
                          live: live, colour: confirming ? Theme.warning : .secondary,
                          keepsColour: confirming) {
            if !item.pinned || confirming {
                store.remove(item.id)
                confirmingRemove = nil
            } else {
                confirmingRemove = item.id
            }
        }
        .help(item.pinned ? "Pinned — click twice to delete" : "Delete")
    }

    /// The text going out, drawn behind the row in the accent colour. It fills as the
    /// characters are typed, flashes full when the last one has gone, and when cancelled
    /// stays where it stopped until the mark is let go. Behind the text, never as its
    /// colour — the accent is whatever the user picked, and yellow text is unreadable.
    private struct TypingFill: View {
        let mark: TypingMark

        var body: some View {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor.opacity(mark.phase == .finished ? 0.45 : 0.28))
                    .frame(width: geometry.size.width * (mark.phase == .finished ? 1 : mark.progress))
            }
            .animation(.linear(duration: 0.12), value: mark.progress)
            .animation(.easeOut(duration: 0.2), value: mark.phase)
        }
    }

    /// The accent background means "Return acts on this one". Pinning gets a lighter
    /// fill and a stripe instead, so the two never look like the same thing.
    private func rowFill(isSelected: Bool, isPinned: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        return isPinned ? Theme.rowPinned : Theme.row
    }

    /// A row button's target is its whole slot — the same width for every icon and the
    /// full height of the row — not the glyph. At 9 points the glyph alone was a target a
    /// few points across, a different size for each icon, and a click just beside one fell
    /// through to the row and armed the entry instead. Sixteen is about what a glyph and the
    /// gap after it took before, so the icons stay close to where they were.
    private static let buttonSlot: CGFloat = 16

    /// Under the pointer the whole slot lights in the accent, which shows the target
    /// rather than leaving it to be guessed from the glyph. The glyph turns primary there:
    /// an accent pin on an accent fill would all but vanish, and the accent is not ours to
    /// pick a contrast for.
    private func iconButton(
        _ symbol: String, key: String, live: Bool, colour: Color = .secondary,
        keepsColour: Bool = false, action: @escaping () -> Void
    ) -> some View {
        let lit = live && hoveredButton == key
        return Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9))
                .foregroundStyle(lit && !keepsColour ? Color.primary : colour)
                .frame(width: Self.buttonSlot)
                .frame(maxHeight: .infinity)
                .background {
                    if lit {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.3))
                            .padding(.vertical, 2)
                    }
                }
                .contentShape(Rectangle())
                .background {
                    if live {
                        PointerTracker { inside in
                            if inside { hoveredButton = key } else if hoveredButton == key { hoveredButton = nil }
                        }
                    }
                }
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
            Text(settings.hotkey.description).padding(.trailing, 8)
            Button(confirmingClear ? "sure?" : "clear") {
                if confirmingClear {
                    store.clearUnpinned()
                    confirmingClear = false
                } else {
                    confirmingClear = true
                }
            }
            .buttonStyle(.plain)
            // Same colour as a pinned row's delete confirmation: both are a destructive click
            // waiting for a second one, and the accent could be any colour at all.
            .foregroundStyle(confirmingClear ? Theme.warning : Color.secondary)
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
