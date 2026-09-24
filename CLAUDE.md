# Toothpaste

A macOS menu-bar clipboard history manager. Its defining feature: it pastes by
**simulating keystrokes** instead of using ⌘V, so it works where the normal paste
path is blocked or unreliable — VM consoles, remote desktop sessions, browser-based
terminals, VNC/Citrix windows, some Java and Electron apps.

Inspired by [0xpaste](https://github.com/mypetcheetah/0xpaste) (Windows, Electron).
This is a native rewrite, not a port — see *Divergences from 0xpaste* below.

## Status

**Working and in daily use.** Capture, the panel, keystroke delivery into both local
apps and RDP sessions, typing profiles, a settings window and in-app updating are all
built and verified. Roughly 4,500 lines of Swift, a 2.4 MB app.

**`PLAN.md` is the source of truth** for what was decided and why — it carries the
measurements behind the typing engine, which are not guessable from the code. Keep it
current when behaviour changes, and update this file when the architecture does. It is
a public development log, so write entries for a stranger: state what was measured and
what it means, not who asked for what.

Not built, by decision rather than omission: the 0xpaste visual styling (phase 2) and
the click-to-target overlay. (The hotkey was once on this list; it has been configurable
since phase 3 — see gotcha 7.)

## Version control

Repo at `github.com/erymantho/mac-toothpaste`, added 2026-09-09 when distribution was
settled as "clone and build".

**Committing and pushing to this repo is authorised** (granted 2026-09-09). Keep
commits scoped to one change with a message that says why, not what. This authorisation
is specific to this repository: it does not extend to creating other repos, adding
remotes, or publishing anywhere else.

**Changes to the app itself wait for the user before they are pushed** (2026-09-15).
Build it, `make install` it, say what changed and what to look at, then stop. They test
and finetune first; push and tag only once they say so. This covers behaviour, UI, the
typing engine, defaults, anything someone would notice while using it.

Documentation, README, plan entries, scripts and build fixes stay autonomous. There is
nothing to try out in those.

Local commits are fine either way. The gate is the push, because other people now pull
from this repo and a version they receive should be one that has actually been used.

**Tag annotations are user-facing copy.** The app shows the annotation of a tag as that
version's release notes, in Settings → Updates — before an update, and after one for as
long as that launch lasts. Write them for someone deciding whether to take the update, and do not open
with the version number: the UI already states it one line above.
**Split them into what is new and what was fixed**, because that is the distinction the
people using the tool asked to see. `ReleaseNotes` reads labels on a line of their own,
flush left:

```
One or two sentences for everyone, if there is something everyone must know.

New:
- Drag an entry to a field to click and type there. Toothpaste posts a mouse
  click as well as keystrokes for it.

Fixed:
- Clicking a row while another window was in front took two clicks.
```

`New:` and `Fixed:` are the two that matter; `Changed:` and `Removed:` exist for what is
neither. Singular and common variants are accepted too (`Bug fix:`, `Feature:`,
`Improvements:`), and any other short capitalised heading after the first label —
`Known issues:` — becomes a section of its own under its own words rather than being
folded into the one above. Numbered and `+` lists read as bullets. Text after the last
section belongs to it, so anything addressed to everyone goes in the summary, first. **Never use Markdown headings.** `git tag -F` cleans the message by deleting every
line that starts with `#`, so `### New` vanishes between writing the tag and reading it —
measured on 2026-09-23. An annotation without labels still reads as one block of prose,
which is what every tag up to 1.2.1 is.
Wrap them for git, not for the window: `ReleaseNotes` joins wrapped lines before anything
displays them, because re-wrapping already-wrapped text to a narrower box strands two or
three words on a line of their own and reads as broken alignment.
**The CHANGELOG entry and the tag annotation are two different texts.** Pasting the
Unreleased section into a tag was measured: git deletes all its `###` headings, so it
parses as one summary; and with labels put in place of the headings, each follow-up
paragraph of an entry becomes a bullet of its own. Write the annotation separately — one
paragraph per bullet — and before tagging, run it through `git tag -F` in a scratch repo
and back through `ReleaseNotes`.
**Plain text.** Only a span in backticks is formatted (as code). There is deliberately no
Markdown: a parser was tried and it ate the backslashes out of `\\fileserver\share`,
decoded entities, and made live links out of URLs in text that comes from whatever remote
a clone follows.
Signed tags are fine — everything from a `-----BEGIN` line on is dropped — and a
lightweight tag reads as empty rather than showing its commit message. Tags are ordered by
their parsed version, not by name, and where two name the same version the annotated one
is kept.
The app shows every version since the one someone is running, so a fixes-only release does
not hide the features of the one before it — **but only from 1.3.0 on.** A 1.2.x copy shows
the newest tag alone, as raw text. While anyone may still be on 1.2.x, a follow-up release's
annotation should repeat what the previous one added.

**Releasing, in this order — the updater depends on every step:**
0. Pick the number from what the annotation says: anything under `New:`, `Changed:` or
   `Removed:` raises the middle number, fixes alone the last. 1.3.0 was the first release
   numbered this way.
1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist` in the
   commit that will be tagged. The updater compares tags against that string: tag a commit
   that still says the old version and every copy is offered the same update forever.
2. Push `main` first. `update.sh` runs `git pull` on the branch, not on the tag, so a tag
   whose commit is not on `main` yet installs the old code and offers itself again.
3. Tag with `git tag -a -F`, the annotation written and round-tripped as above, then push the
   tag.
4. **Never move or re-create a tag once it is pushed.** Measured: every clone that already
   has it then refuses the new one ("would clobber existing tag"), and `git fetch` exits 1
   on every check from then on. 1.3.0 and later fetch tags with `--force` and survive it;
   1.2.x copies do not, and would never be offered an update again. Get the annotation right
   before pushing; a mistake is fixed in the next version's notes.

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
make appearances        # render every window under Automatic/Light/Dark, offscreen,
                        # to dist/appearances — see gotcha 13
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
    ClickCatcher.swift         a row's click, caught in AppKit — see gotcha 16
    DragPreview.swift          the entry carried beside the pointer — see gotcha 19
    UpdateFailedView.swift     a failed update, on the launch it produced
    ReleaseNotesView.swift     release notes, shown the same way before and after an update
    WindowDragBlocker.swift    where dragging the panel must not start
    WindowDragHandle.swift     where it must — see gotcha 15
    PanelState.swift           what the panel shows while open (armed item, status,
                               the entry being typed and how far along)
    SettingsWindowController.swift
    SettingsView.swift         General / Typing profiles / Layout check / Updates
    HotkeyRecorder.swift       records a new hotkey inside the settings window
    OnboardingView.swift       the Accessibility permission, explained
    Theme.swift                the greys and status colours, per appearance,
                               and which appearance the app renders in
  System/
    Hotkey.swift               Carbon RegisterEventHotKey
    FrontmostWatcher.swift     tracks the app a paste would go to, live
    LaunchAtLogin.swift        SMAppService
    Settings.swift             UserDefaults-backed preferences
    KeyCombo.swift             a hotkey as stored and shown
    AppVersion.swift           version, commit and source path stamped by bundle.sh
    Updater.swift              version check, and handing the update to the helper
    ReleaseNotes.swift         a tag annotation split into new / changed / fixed / removed
Sources/TypeSpike/            diagnostic CLI: --dump-map, --list-layouts, typing tests
Resources/Info.plist          bundle template (LSUIElement = 1)
Resources/Toothpaste.icns     generated by scripts/make-icon.sh
scripts/bundle.sh             assembles dist/Toothpaste.app
scripts/select-sdk.sh         works around the CLT 6.4 SDK — see the section above
scripts/create-cert.sh        the one-time signing certificate (make cert)
scripts/make-icon.sh/.swift   generates Resources/Toothpaste.icns
scripts/inspect-pasteboard.swift  dumps the types on the pasteboard, for debugging
scripts/install.sh            copies it to ~/Applications and runs it from there
scripts/verify-capture.sh     regression check for capture and persistence
scripts/render-appearances.sh both palettes without switching the machine over
scripts/render-appearances.swift  the renderer it compiles against the real sources
scripts/update.sh             pulls and reinstalls after the app it replaces has quit
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
   - **And every modifier flag needs its left/right bit beside it.** A real keyboard sends
     Shift as `maskShift` *plus* `0x02`, IOKit's `NX_DEVICELSHFTKEYMASK`, which says which
     Shift is down; Option comes with `0x20`. Windows App 11.4 re-syncs the modifiers it has
     sent against every key event and reads only that device bit, so a key carrying
     `maskShift` alone makes it release our Shift right before the key: `#` arrives as `3`,
     `A` as `a`. Read from the client itself — `MacKeyboardDriver.synchronizeModifiers`, with
     `LeftShiftKeyMask = 0x2` — not guessed. `CGEvent` sets these bits on its own when it
     creates a modifier event; assigning `flags` afterwards is what threw them away. See
     PLAN.md, *Shift was released right before the key*.
   - **Windows App's Unicode keyboard mode is not ours to fix.** On 11.4.1 it typed nothing
     at all, from the Mac's own keyboard as well. Setting the event's unicode string to the
     intended character made no difference there either — tried and reverted. Scancode is
     its default, and the mode this tool is built for.
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
12. **A view that paints its own background owes you both appearances.** The panel
    draws its own surfaces instead of using the window's, but its text uses the
    semantic colours, which follow the system appearance regardless. Fixed greys
    therefore only appear to work: chosen against Dark Mode they turn into near-black
    text on near-black fills the moment someone runs Light Mode. Nothing warns you,
    because each half is individually reasonable. All surface colours live in
    `Theme.swift` and every one of them states both values — add colours there, not
    inline. The same applies to `.orange` and `.green`: the system versions reach about
    2:1 against a light background, which is below readable.
    And to `Color.accentColor` for text: it is whatever accent the user picked, so its
    contrast is not ours to choose. Measured in light mode: yellow 1.56:1, green 2.43:1,
    orange 2.57:1, graphite 2.88:1 — and a green accent is the same hue as `Theme.ok`, which
    erased the difference between the *New features* and *Bug fixes* headings. Those use
    `Theme.newFeature` (5.3:1 to 7.0:1 on every background it can sit on) and `Theme.ok`
    (5.1:1 to 6.0:1 in light, 6.4:1 to 8.2:1 in dark — its light value was darkened once
    more for this, having read 4.28:1 on the 0.925 window background of macOS 14 and 15).
    The panel followed the same rule: the armed banner's words are primary with only its
    icon, wash and border in the accent, and the *clear* confirmation uses `Theme.warning`
    like a pinned row's delete. The accent is left on things that are not text — the pin
    stripe, the armed border, the query caret, and since 1.4.0 the fill behind a row being
    typed, the wash under the pointer and the outline of the dragged card. Each sits
    *behind* or *around* primary text, never as its colour. `make appearances` cannot show
    other accents: `.accentColor(_:)` on a view does not reach `Color.accentColor`, which
    follows the system setting — measured — so yellow has to be reasoned about, not
    rendered. The hover wash is tracked by `ClickCatcher` with an `.activeAlways` tracking
    area rather than `onHover`, for the reason in gotcha 16: the panel is rarely active.
    `Settings.appearance` can override the system choice; it is applied by setting
    `NSApp.appearance`, so every window follows at once and windows opened later inherit
    it. Apply it from the delegate's launch, never from `Settings.init` — that object is
    a stored property of the delegate, and whether `NSApp` exists that early depends on
    the order of two lines in `main.swift`.
13. **Test both appearances without switching the machine over.** `make appearances`
    compiles the real sources against `scripts/render-appearances.swift` and renders
    every window offscreen through `NSHostingView` + `cacheDisplay`, once per appearance
    choice. Run it after touching anything in `UI/`. Two things it does that any
    variation on it must also do: pick the appearance by assigning to
    `Settings.appearance` rather than calling `apply()`, since a `Settings` built
    afterwards applies the stored choice over the top; and leave `window.appearance`
    unset, so the window can only inherit from `NSApp` — which is the mechanism being
    tested. It points `HOME` *and* `CFFIXED_USER_HOME` at a scratch directory, because
    `HistoryStore` saves on a timer and would otherwise write its mock items over the
    real `history.json`.
    One thing it cannot show: an offscreen window is never key, so AppKit draws its
    controls unemphasised — an enabled `Toggle` renders grey rather than accented. Read
    the knob position, not the colour. SwiftUI colours set explicitly, `Color.accentColor`
    included, are unaffected.
    **Look at the dark renders too, not only the light ones.** `cacheDisplay` captures the
    content view and not the window's own background, so a window whose SwiftUI content
    paints no background came out transparent — white text on nothing in dark mode, a
    blank image. The post-update window, then `WhatsNewView`, rendered like that from the
    day it was added, and so did the onboarding window, and nobody saw, because only their light renders were being
    opened. `shoot` now paints
    `windowBackgroundColor` behind every window, as the real window does; the panel is
    exempt because it is meant to be transparent around its corners.
    **It refuses to run against the real support folder.** Building an `Updater` deletes the
    update markers it finds, and the renderer plants fake ones; run with the real folder it
    would wipe a pending report and leave a fake failure for the app to show. The script
    sets `CFFIXED_USER_HOME` — `HOME` alone does not redirect Foundation — and the renderer
    checks it.
    And render a view inside the container it lives in. `ReleaseNotesView` as a bare root
    reported an ideal height of several thousand points; inside a `Form` or a `ScrollView`,
    as in the app, it lays out normally.
14. **An app cannot replace itself while it is running.** `install.sh` quits Toothpaste
    before it copies, so anything supervising an in-app update would be the thing being
    replaced. `Updater.update()` spawns `scripts/update.sh` detached, hands it this
    process's pid, and calls `NSApp.terminate`; the helper waits for that pid to go before
    it touches anything and is reparented to launchd when it does. There is no relaunch
    step, because `install.sh` already ends with `open` — the helper only has to bring the
    *old* copy back when the build fails, since nothing else will.
    - **The installed copy has no idea where the source is.** `bundle.sh` stamps
      `ToothpasteSource` beside `ToothpasteCommit` for exactly this. A checkout that has
      moved is reported as its own state rather than discovered halfway through.
    - **`GIT_TERMINAL_PROMPT=0` is mandatory, not defensive.** Git run from an app bundle
      has no terminal, so a repository that wants credentials blocks forever on a prompt
      nobody can see and the check simply never returns. Same reason every git call
      carries a timeout.
    - The check is `git fetch --tags` against the clone's *own* remote, so a fork updates
      from the fork. It moves remote-tracking refs and tags only, never the working tree
      or the current branch, which is what makes it safe to run unattended.
    - `git pull --ff-only`, so local commits or a dirty tree stop the update rather than
      being merged around.
    - **Tags are fetched with `--force`.** Without it a tag moved on the remote makes every
      later fetch exit 1, silently under `--quiet`, and nothing is ever offered again.
    - **The helper that runs is always the old version's.** `Updater.update()` starts
      the checkout's `update.sh` before pulling, and `git pull` replaces the file with a
      new one rather than rewriting it — measured, the inode changes — so bash goes on
      reading the old script to the end. Any change to `update.sh` therefore takes effect
      one update later, and so does anything the *old* app shows before an update. This is
      why the first release with the success marker could not produce its own report.
    - **The outcome is reported by marker file, on the launch the update produced.**
      `update.sh` writes `update-succeeded` with the version it replaced, or
      `update-failed` with a reason; `Updater` reads and consumes both in `init`. A failure
      opens `UpdateFailedView`; a success opens nothing, and is what makes Settings →
      Updates list every release since the version replaced, for that launch, rather than
      only the running one. The failure marker used to wait until dismissed, so closing the
      report with the window's close button instead of *Done* brought it back on every later
      launch.
      - The **success** marker is written *before* `make install`, and withdrawn if it fails.
        `install.sh` ends by opening the new app, which reads its markers as it starts, so a
        marker written after `make install` returned was racing the app it was meant for.
        Written before, it is always older than the binary that update produces — so it
        counts only when it *is* older than the running binary. An old copy opened while the
        build is running, or the same copy after an update that was cut off, is older than
        the marker, leaves it alone, and the launch it belongs to still finds it. Read by the
        wrong launch, it had reported an update that had not happened, and the real new
        version then started without a word.
      - A **failure** marker counts only if it is newer than the running binary. A failed
        update relaunches the old binary, which is older; a marker left by an earlier failure
        — 1.2.x never removed its own — is older than a build installed since, and would
        otherwise report a successful manual update as a failed one.
      - `justUpdatedFrom` is shown only when it is a version number. An older `update.sh`
        could write PlistBuddy's own error text into it.
      These are in 1.3.0's `update.sh` and `Updater`, so — see the point above — the script
      fixes take effect from the first update *after* 1.3.0. It has to work this way round because by the time
      the outcome is known the app that asked for it no longer exists. An ordinary launch
      finds no marker and says nothing.
      **A failure must open a window; a success need not.** A failed update brings the old
      version back, which looks exactly like a successful one, and a note in the settings
      window alone went unread. Success had a window too, from 1.3.0 until 1.4.0, and it
      was removed as one window too many around an update: its notes had just been read in
      the Updates tab, and the arrow leaving the menu bar icon already says it worked. Do not
      remove the failure window on the same reasoning — it is the only thing that tells the
      two outcomes apart.
15. **`isMovableByWindowBackground` does nothing inside an `NSHostingView` on macOS 27.**
    The panel became impossible to move, and it looks like a bug in our code from every
    angle: the flag is still set, and `mouseDownCanMoveWindow` on the hit view still reads
    `true`. SwiftUI simply consumes the mouse-down before AppKit can start a drag.
    Bisected against a panel with a plain `NSView` content view on the same machine and
    the same displays, which drags fine — so it is the hosting, not the window, not the
    display, and not the code that changed. Do not go looking in `PanelController`.
    - **The fix is `performDrag(with:)` from a real `NSView`** — `WindowDragHandle`.
    - **It has to be an `overlay`, not a `background`.** As a background it only receives
      clicks where SwiftUI draws nothing whatsoever; over a `Text` SwiftUI claims them,
      which leaves a draggable strip of about fifteen points and nothing else. Measured.
    - **Anything that must stay clickable goes above it in z-order**, and that works: a
      `Button` and a `Menu` stacked over the handle both still respond. A `ZStack` does
      not make its layers avoid each other, though, so reserve the controls' width with a
      `.hidden()` copy inside the text layout or they will overlap.
    - The handle must not become first responder, or type-to-search breaks the first time
      someone drags the panel.
    - Do not delete `WindowDragBlocker`. The deployment target is macOS 14, where
      background dragging still works and brushing a row would otherwise move the panel.
16. **The panel is usually not the key window, so it has to accept the first mouse —
    and `acceptsFirstMouse` alone will not do it.** Arming an item means clicking into
    another window, so the panel is open and inactive for most of its life and every
    return trip was spending a click on activation instead of on the row under the
    pointer.
    `FirstMouseHostingView` overrides `acceptsFirstMouse` on the hosting view, which is
    necessary and not sufficient: **SwiftUI's tap gesture ignores it**. The proof was in
    one window — a `WindowDragHandle` moved the panel on the first click while a row two
    points below it still needed two. AppKit event paths honour the flag; SwiftUI
    gestures do not.
    So a row's click is caught by `ClickCatcher`, a real `NSView`, on the same terms as
    the drag handle: overlay rather than background, with the per-row buttons stacked
    above it.
    **The split runs inside SwiftUI, not between SwiftUI and AppKit.** Measured in the
    finished panel: a `Button` *does* act on the activating click, while `.onTapGesture`
    on the same row did not. So `acceptsFirstMouse` is honoured by one SwiftUI control
    path and ignored by another, which is worth knowing before assuming either way —
    both assumptions were made here and both were wrong once.
    The consequence is live rather than theoretical: a row's delete button fires on an
    activating click. The history is ephemeral, so an unpinned entry lost that way costs
    little; a pinned one is persisted and does not come back. Only pinned rows therefore
    ask twice — the same self-disarming confirmation the `clear` button uses. Guarding
    both would have put friction on the case where nothing is at stake, which is most of
    them.
17. **Anything the app wants noticed has to reach the menu bar.** It is the only surface
    that is always on screen. The settings window is not somewhere anyone opens
    unprompted, which is how an available update sat unseen — it was in settings and in
    the right-click menu, and both required already going to look. `applyRestingGlyph()`
    owns the resting state, and every transient flag must restore *through* it rather
    than to a hardcoded icon, or the flag quietly erases whatever it was covering.
18. **The click that picks the destination has to finish before typing starts.** It is
    not only a selection: it is also the click that puts the caret in the field. So the
    outside-click monitor matches mouse *up*, not down — on mouse-down the typing could
    begin while the button was still held.
    That is the cheap half. Over RDP the click still has a network round trip ahead of it
    before the far side moves its own caret, and nothing local can observe when that has
    happened. `TargetProfile.initialDelayMs` covers the rest, which is why it is per
    profile and adjustable rather than a constant: too low and everything types perfectly
    into whichever field had focus a moment earlier. **Do not reach for it first.**
    Measured on a real RDP link: the remote default of 200 ms was enough once the trigger
    moved to mouse-up, so raising it would have masked the timing bug rather than fixing
    it, and bought a visible pause before every paste. Reported as "it types, but in the
    wrong field, so I have to select it beforehand" — which is what makes a username and
    a password cost two extra clicks.
19. **The dragged entry is a window of its own, and three things about it are not
    decoration.** `DragPreview` draws the row — its real text, fill and pin stripe — tilted
    three degrees beside the pointer while drag-to-type carries it, outlined in the accent
    with a glow that comes up with the pickup. On a pinned card the stripe merges into that
    outline, which was accepted: the card says what is travelling, the list says what is
    pinned.
    - **Beside the pointer, not under it.** The click lands on the pointer's tip; a card over
      the tip would hide the field being aimed at. The pointer is the ordinary arrow — the
      crosshair it used to become was dropped — and the card sits clear of the arrow.
    - **Invisible to the mouse, and gone before the click.** `ignoresMouseEvents`, at
      `CGWindowLevelForKey(.draggingWindow)` — the level macOS draws its own drag images at —
      and ordered out in `mouseUp` before `onDrop` posts anything.
    - **A masked entry travels masked.** The card gets the text the row shows, dots
      included; dragging a secret across the screen must not be what reveals it.
    The shadow is SwiftUI's, not the window's: a window shadow is computed once when the
    window appears and stays square under a card that has since tilted. And a row can leave
    the list mid-drag, so `ClickCatcher` also ends the drag in `viewWillMove(toWindow: nil)`,
    or the card would stay on screen.
20. **The pointer vanishes while typing, and that is left alone.** The destination app
    hides it on every key event, as it does for a person typing, until the mouse moves.
    `NSCursor.setHiddenUntilMouseMoves(false)` from here does nothing, since this app is
    not in front. A one-point `mouseMoved` there and back does bring it back — measured,
    locally and over RDP — and was deliberately not kept: it is a mouse event nobody asked
    for, posted to undo something that ends on its own. See PLAN.md, *The pointer that
    stays hidden after typing*.

## Divergences from 0xpaste

- **No click-to-target overlay, and none needed.** 0xpaste captures a click point with
  a fullscreen overlay. Here, choosing an item *arms* it: the panel stays open and the
  next click in any other window is the destination. Same outcome — you pick the exact
  field, including inside a remote session — without synthetic mouse clicks or an
  overlay. `FrontmostWatcher` names that destination in the header, tracked live
  because the panel stays open while you click around.
  Since 2026-09-23 there is a setting that does synthesise a click: `Settings.dragToType`
  makes dragging an entry out of the panel click where it is released and type there. It
  shipped off by default in 1.3.0 and was **switched on by default** later the same day,
  once it had been in use. It is still the only thing in the app that posts a mouse event
  rather than a key event, so the README says so up front — see the security posture.
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
- Masking is **visual only** — it hides text on screen, it is not encryption. It is also
  switchable, via `Settings.maskConcealed`, and defaults to on: a secret should not end up
  on screen because nobody got round to deciding. Switching it off changes display and
  nothing else — concealed entries stay out of `history.json` either way, and that rule
  must not become reachable from a display preference.
- Items marked concealed by the source app are **never written to disk** (memory only).
- The app types your clipboard contents as keystrokes, which is functionally an
  autotyper. That is the point, but it deserves a clear-eyed mention.
- **With `Settings.dragToType` on, it also clicks.** Dropping an entry makes the app post
  a mouse click at that point before typing, which makes it an autoclicker as well and
  changes the sentence someone has to say to whoever manages their machine. **It is on by
  default**, so that sentence applies to everyone who has not switched it off — the README
  states it in *What this is, plainly*, not in small print. Switched off, "this app posts
  keystrokes and nothing else" is true again. It also adds a failure the arm-and-click
  flow does not have: release over something that is not a text field and that is what
  gets clicked.
- **The app can fetch and run code.** Settings → Updates pulls and rebuilds from the
  checkout it was built from, then restarts. That is `git pull` plus `make install` on the
  user's own clone — the same commands they would type — but it means a button inside the
  app builds and runs whatever is in the repository. Clone-and-build already had that
  property; the button removes the terminal from in front of it. Say so in the
  confirmation, and never make it automatic.
- **Checking for updates is the only network access the app has.** `git fetch --tags`
  against the clone's own remote; nothing about the user or the clipboard is sent, and
  `Settings.checkForUpdates` switches it off. Before this the app talked to nothing at
  all, which is a property worth giving up deliberately rather than by accident.

## Conventions

- Small files, one responsibility each. No dependency injection frameworks, no
  protocols-for-one-implementation.
- UI state classes are `@MainActor`.
- Comments explain *why*, and only where the reason is not obvious from the code.
  The macOS gotchas above are exactly the kind of thing that earns a comment.
- Do not add a test framework for the MVP. Verify by running the app; the plan
  carries an explicit manual test matrix.
