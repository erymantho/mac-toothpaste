# Toothpaste

A macOS menu-bar clipboard history manager. Its defining feature: it pastes by
**simulating keystrokes** instead of using ⌘V, so it works where the normal paste
path is blocked or unreliable — VM consoles, remote desktop sessions, browser-based
terminals, VNC/Citrix windows, some Java and Electron apps.

Inspired by [0xpaste](https://github.com/mypetcheetah/0xpaste) (Windows, Electron).
This is a native rewrite, not a port — see *Divergences from 0xpaste* below.

## Status

**Working and in daily use.** Capture, the panel, keystroke delivery into both local
apps and RDP sessions, typing profiles, and a settings window are all built and
verified. Roughly 2,600 lines of Swift, a 1.6 MB app.

**`PLAN.md` is the source of truth** for what was decided and why — it carries the
measurements behind the typing engine, which are not guessable from the code. Keep it
current when behaviour changes, and update this file when the architecture does. It is
a public development log, so write entries for a stranger: state what was measured and
what it means, not who asked for what.

Not built, by decision rather than omission: the 0xpaste visual styling (phase 2), a
configurable hotkey, and the click-to-target overlay.

## Version control

Repo at `github.com/erymantho/mac-toothpaste`, added 2026-09-09 when distribution was
settled as "clone and build".

**Committing and pushing to this repo is authorised** (granted 2026-09-09). Keep
commits scoped to one change with a message that says why, not what. This authorisation
is specific to this repository — it does not extend to creating other repos, adding
remotes, or publishing anywhere else.

## Stack

- Swift 6 toolchain, SwiftUI for views, AppKit for the menu bar, panel window and
  event plumbing.
- Swift Package Manager. **There is no Xcode project** — only Command Line Tools
  are installed, so `xcodebuild` does not exist and `swift build` is the only
  build path. Do not generate an `.xcodeproj`.
- Language mode is pinned to Swift **5** (`.swiftLanguageMode(.v5)`) to avoid
  fighting strict-concurrency errors across AppKit callbacks. Revisit later.
- **Zero third-party dependencies.** Keep it that way unless there is a strong,
  stated reason.
- Deployment target: macOS 14+, Apple Silicon.

## Command Line Tools 6.4 ships an SDK it cannot build against

CLT 6.4 installs a macOS 27 SDK whose SwiftUI declares `@State` and friends as macros,
without shipping the `SwiftUIMacros` plugin that implements them. Every SwiftUI file
then fails with *external macro implementation type 'SwiftUIMacros.StateMacro' could not
be found*. Full Xcode has the plugin; Command Line Tools does not.

`scripts/select-sdk.sh` picks the newest SDK that predates the macro requirement, and
`make` and `bundle.sh` pass what it prints. It returns nothing when the plugin is
present, so the workaround disappears by itself once Apple ships it. Delete the script
and both call sites at that point.

**If a build suddenly fails across every SwiftUI file, check this before the code.** It
arrived with a toolchain update, not with a change to the project.

## Commands

```sh
make build     # debug build (swift build)
make app       # release build + assemble Toothpaste.app + codesign
make run       # alias for install — never run dist/ directly, see gotcha 2b
make install   # copy the signed app to ~/Applications and run it from there
               # THIS is the copy that holds the Accessibility grant
make reset-permission   # clear a stuck Accessibility grant for our bundle id
make verify    # regression-check the clipboard capture path
make clean     # remove .build/ and dist/
```

`make verify` drives the running app with `pbcopy` and asserts against the
`history.json` it writes — no permissions, no UI, no window focus needed. It saves
and restores the real clipboard. Extend it when the store gains behaviour.

`make app` produces `dist/Toothpaste.app`. It is an accessory app: menu bar icon,
no Dock icon, no main window.

## Layout

```
Sources/Toothpaste/
  main.swift                  NSApplication bootstrap (no @main — file is main.swift)
  AppDelegate.swift           lifecycle, status item, arm/deliver flow, wiring
  Clipboard/
    ClipItem.swift             model (text, timestamp, pinned, concealed)
    ClipboardWatcher.swift     NSPasteboard.changeCount polling
    HistoryStore.swift         ordering, dedupe, pinning, cap, expiry, persistence
  Typing/
    KeyboardLayout.swift       character → keystroke map for a chosen layout
    TypingEngine.swift         posts the events, pacing, Esc cancellation
    TargetProfile.swift        how to type into one kind of destination
    ProfileStore.swift         the profiles, and which one a destination gets
    Accessibility.swift        AXIsProcessTrusted gate + prompt
  UI/
    PanelController.swift      NSPanel host, show/hide, remembered position
    PanelView.swift            search, list, rows, profile menu, clear button
    PanelState.swift           what the panel shows while open (armed item, status)
    SettingsWindowController.swift
    SettingsView.swift         General / Typing profiles / Layout check
  System/
    Hotkey.swift               Carbon RegisterEventHotKey
    FrontmostWatcher.swift     tracks the app a paste would go to, live
    LaunchAtLogin.swift        SMAppService
    Settings.swift             UserDefaults-backed preferences
Sources/TypeSpike/            diagnostic CLI: --dump-map, --list-layouts, typing tests
Resources/Info.plist          bundle template (LSUIElement = 1)
Resources/Toothpaste.icns     generated by scripts/make-icon.sh
scripts/bundle.sh             assembles dist/Toothpaste.app
scripts/install.sh            copies it to ~/Applications and runs it from there
scripts/verify-capture.sh     regression check for capture and persistence
```

## macOS specifics that will bite you

These are the non-obvious ones. Read before touching the relevant area.

1. **Accessibility permission is mandatory.** `CGEvent.post` silently does nothing
   without it — no error, no exception, just no typing. Always gate on
   `AXIsProcessTrusted()` and surface the state in the UI.
2. **The TCC grant breaks on every rebuild** when the app is ad-hoc signed, because
   the grant is pinned to the binary's cdhash. Sign with a stable self-signed
   identity so the grant survives rebuilds (see PLAN.md phase 0). Look it up with
   `security find-identity -p codesigning` — **without `-v`**, which hides untrusted
   self-signed roots entirely.
2b. **The grant follows the signature, not the path.** Measured, and it corrects an
   earlier claim in this file. The designated requirement is
   `identifier "com.michaelsmith.toothpaste" and certificate leaf = H"f5d3…"` — no path
   in it — so `codesign --verify -R` confirms `dist/Toothpaste.app` satisfies the
   installed copy's requirement exactly. TCC treats them as the same app, and deleting
   and recreating a bundle changes nothing.
   Run from `~/Applications` via `make install` anyway, for smaller reasons that are
   still real: launch-at-login registers a *path* and `make app` deletes that bundle;
   two registered copies appear twice in Launchpad; and the project folder is
   Nextcloud-synced. Use `make reset-permission` to clear a genuinely stuck grant.
3. **There is no pasteboard change notification.** Polling `NSPasteboard.general.changeCount`
   on a timer is the only option. ~300ms is the normal cadence.
4. **Type with real virtual keycodes, not `keyboardSetUnicodeString`.** This is
   measured, not assumed — see PLAN.md section 3 before touching `TypingEngine`.
   - Unicode mode works locally but is **useless over RDP**: Windows App, Devolutions
     RDM and Omnissa Horizon all read `NSEvent.keyCode`, and the virtual key 0 we
     pass alongside a unicode payload *is* `kVK_ANSI_A` — every character arrives
     as `a`. Keep unicode only as a fallback for characters the layout cannot
     produce, and disable even that in remote mode, where a silent wrong guess is
     worse than a reported gap.
   - **Modifiers must be posted as real Shift/Option key events.** Setting
     `CGEvent.flags` on the character event alone satisfies native Mac apps but not
     RDP clients: `Hello` arrives as `hello` and `@` as `2`.
   - **Dead keys must be composed**, since `" ' ^ ~ é ü` have no direct key on
     U.S. International. Map them as dead-key-then-space (or then-letter).
   - **`UCKeyTranslate`'s `deadKeyState` packs two fields into one `UInt32`.** Only
     the **low 16 bits** mean "a dead key is still pending"; the high word remembers
     the one just consumed, so a successful composition reports e.g. `0x40000`, not
     `0`. Test `state & 0xFFFF == 0`. Getting this wrong silently picks a pairing
     that leaks the accent into the following character and eats the next space.
   - Only character-producing keycodes may complete a dead key. `UCKeyTranslate`
     will happily "flush" an accent against a modifier keycode, which is how a naive
     version chose Right Command as the completion for a double quote.
5. **Newlines are the exception** — they need a real Return key event (virtual key
   36). Split text on newlines, type the segments, post Return between them.
6. **Clear `event.flags` explicitly** and wait for the hotkey's modifiers to be
   released before typing, or held modifiers corrupt the output.
7. **⌃Space is taken** by Input Sources switching on macOS. It cannot be the default
   hotkey the way it is on Windows. The shortcut is configurable — `KeyCombo` plus
   `HotkeyRecorder` — and defaults to ⌃⌥V. A recorder inside our own window only needs
   a *local* `NSEvent` monitor returning nil to swallow the keystroke; the hard version
   of that problem is a global recorder, which this is not.
8. **Honour the pasteboard convention types**: `org.nspasteboard.ConcealedType`
   (password managers mark secrets with it — treat as concealed),
   `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType`
   (do not store at all; prevents feedback loops with other clipboard tools).
9. **A non-activating `NSPanel` won't take keyboard focus** — which is what makes
   focus restore easy, but also means the search field gets no keystrokes. Override
   `canBecomeKey` to get Spotlight-style behaviour: panel takes key focus without
   fully activating the app.
10. **Secure Input Mode does not block us** — tested, not assumed. Typing works into
    real password fields, both native UI fields and Terminal. Worth knowing in both
    directions: it is why the tool is useful for credentials, and it is the sharpest
    demonstration that this is functionally an autotyper. Say so plainly in any
    user-facing description.
11. **Multi-display setups are the normal case here, not the exception.** Panel
    placement must pick the screen the mouse is on, not the main one. And
    `screencapture -x out.png` grabs a single display — a window you are looking for is
    often on another, so pass `-D 1|2|3` before concluding something did not happen.

## Divergences from 0xpaste

- **No click-to-target overlay, and none needed.** 0xpaste captures a click point with
  a fullscreen overlay. Here, choosing an item *arms* it: the panel stays open and the
  next click in any other window is the destination. Same outcome — you pick the exact
  field, including inside a remote session — without synthetic mouse clicks or an
  overlay. `FrontmostWatcher` names that destination in the header, tracked live
  because the panel stays open while you click around.
- **Dead-key handling is required after all**, unlike the early assumption that
  macOS made it go away. See point 4: RDP targets force virtual keycodes, which
  brings the whole layout problem back.
- **No PowerShell-equivalent subprocess.** Typing happens in-process via CGEvent;
  shelling out to `osascript` would make the Accessibility permission attribution
  unreliable.

## Security posture

Be honest about this in the UI and the README:

- **Only pinned entries are persisted.** The history is a session thing: whatever was
  copied is gone on restart, and pinning is how the user says "this one outlives the
  session". That, rather than encryption, is the answer to having real work content in
  the file — most of it is never written at all.
- What is written is **plaintext JSON** in `~/Library/Application Support/<bundle-id>/`.
- **Concealed items are excluded even when pinned.** A password manager marked them
  secret; writing a secret to a plain file because someone pinned it would quietly
  undo that.
- `Settings.retentionHours` additionally forgets unpinned entries past a chosen age
  *within* a running session. Defaults to never.
- Masking is **visual only** — it hides text on screen, it is not encryption.
- Items marked concealed by the source app are **never written to disk** (memory only).
- The app types your clipboard contents as keystrokes, which is functionally an
  autotyper. That is the point, but it deserves a clear-eyed mention.

## Conventions

- Small files, one responsibility each. No dependency injection frameworks, no
  protocols-for-one-implementation.
- UI state classes are `@MainActor`.
- Comments explain *why*, and only where the reason is not obvious from the code.
  The macOS gotchas above are exactly the kind of thing that earns a comment.
- Do not add a test framework for the MVP. Verify by running the app; the plan
  carries an explicit manual test matrix.
