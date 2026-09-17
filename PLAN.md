# Toothpaste — Build Plan

A macOS clipboard history manager that pastes by simulating keystrokes.
Native Swift, menu-bar only, MVP first then finetune.

---

## What this document is

A development log, kept as the work happened, over two days in September 2026. It
records decisions and the reasons behind them — including the approaches that were
tried and failed, which is most of the value.

**If you only want to work on the code, read `CLAUDE.md` instead.** It carries the
eleven macOS pitfalls in a form you can act on. This file is for when you want to know
*why* something is the way it is, and what happens if you change it back.

Some of it reads like a confession. That is deliberate. Several conclusions here were
wrong on the first attempt and are corrected in place, with the original reasoning left
visible — a test that proved nothing because Gatekeeper was disabled on the machine
running it, a dead-key composition that looked right and silently ate the following
space, a diagnosis credited to two changes when only one of them mattered. Those are
worth more than a clean narrative would be.

Written collaboratively with [Claude Code](https://claude.com/claude-code): the
measurements, the failures and the corrections are all real and were run against real
RDP sessions, real password managers and real hardware.

---

> Checkbox key: `[x]` done · `[~]` deliberately dropped, with the reason · `[·]` part
> of a phase that was parked, not an open task. A bare `[ ]` is genuinely outstanding.

## Where this stands — end of 2026-09-08

Built, working, in use. Phases 0, 1 and 3 are done; phase 2 (styling) and phase 4 were
dropped or deferred by decision, not left undone by accident.

**Read this document for the *why*.** The code says what it does; what it cannot say is
that Unicode typing was tried first and produced 53 letter `a`s over RDP, that
modifier flags on the character event are not enough for an RDP client, or that
`UCKeyTranslate`'s dead-key state hides its meaning in the low 16 bits. Those cost most
of the day and are all recoverable only from here. Section 3 is the important one.

**The shape of the thing:** ⌃⌥V opens a panel; choosing an item arms it; the next click
in any window is the destination; Esc cancels. Which keyboard layout to map against and
how fast to type is a *profile*, chosen from the destination app, because local apps and
remote sessions want opposite settings. Nothing unpinned is written to disk.

**Known limitations, all deliberate:** the hotkey is fixed, there is no visual styling
beyond plain and legible, and the layout a remote machine uses has to be told to us —
no local code can discover it.

**If you change the typing engine, run the diagnostic** (`swift run typespike
--dump-map --layout <id>`) and re-test against a real RDP session. The unit of truth
here is what arrives on the far end, and nothing in the build catches that.

---

## 1. Why native Swift and not Electron

0xpaste is Electron + a PowerShell `SendKeys` subprocess. Mirroring that on macOS
is the worse path here:

| | Electron | Native Swift |
|---|---|---|
| Toolchain present | **No** — Node/npm are not installed | **Yes** — Swift 6.3.3 via CLT |
| Keystroke simulation | needs a native module: `robotjs` (unmaintained since 2019) or `nut.js` (v4+ is commercially licensed) | `CGEvent`, in the SDK |
| Per-character pacing | the `osascript` fallback gives none — one subprocess per character, or no timing control at all | a delay between two posted events |
| Accessibility permission | flaky attribution when a subprocess posts events | granted directly to the app |
| Keyboard layouts / dead keys | must be handled | **disappears** — `keyboardSetUnicodeString` is layout-independent |
| App size | ~150 MB | ~2 MB |

The deciding row is **pacing**. On Windows, `SendKeys` ships with the OS, so 0xpaste
gets keystroke simulation for free. macOS has no equivalent reachable from Node.
The closest analogue — `osascript … keystroke` — routes through the active keyboard
layout (so the dead-key problem comes back), needs arbitrary clipboard text
interpolated into an AppleScript source string (an injection vector), and offers no
per-character timing: you either send the whole string at once, or pay a subprocess
round-trip per character. Slow, metered typing into remote consoles is the entire
point of this tool, so that is not a detail we can trade away.

The dead-key handling that 0xpaste needs on Windows also simply does not exist as a
problem on macOS, which removes a large chunk of the original's complexity.

What Electron would genuinely win: the reference UI is HTML/CSS that could be
lifted from 0xpaste more or less directly, which is a real head start on phase 2.
Global hotkeys, clipboard polling, the panel window and focus restore are all fine
in Electron — the gap is only the typing engine, and the always-running footprint
(~150 MB on disk versus ~2 MB).

The cost of going native: Swift, and no code reuse from 0xpaste. For a small
personal tool with no cross-platform ambition, that is a good trade.

---

## 2. Decisions to confirm before we start

Walk through these; everything below assumes the **bold** default.

1. **App name / bundle ID** — **`Toothpaste`**, `com.michaelsmith.toothpaste`.
   Both live in one place (`Resources/Info.plist` + `scripts/bundle.sh`), so this
   is cheap to change now and annoying later (the Accessibility grant is keyed to
   the bundle ID).
2. **Default hotkey** — **⌃⌥V**. It cannot be ⌃Space, which macOS reserves for
   switching input sources. ⌥Space is Raycast/Alfred territory, ⇧⌘C is Maccy's.
   Configurable in phase 3 either way.
3. **Click-to-target overlay** — **defer to phase 4.** 0xpaste needs a fullscreen
   overlay to capture a click target because Windows makes focus restoration
   awkward. macOS lets us remember the frontmost app and reactivate it, which
   covers the normal case with far less machinery.
   Confirmed targets are normal Mac apps **plus Windows App (RDP) and Devolutions
   Remote Desktop Manager**. Focus restore should still be enough there: the remote
   machine keeps its own focus state, so reactivating the RDP window puts the caret
   back where it was on the remote side. Verified early in phase 1 rather than
   assumed — if reactivation resets remote focus, the overlay moves up.
4. **Text only for the MVP** — **yes.** No images or file references in history.
5. **Self-signed code-signing certificate** — **recommended.** Two minutes in
   Keychain Access. Without it, macOS revokes the Accessibility permission on
   every single rebuild and you re-approve in System Settings each time. With it,
   the grant sticks. Skippable, but the dev loop gets tedious fast.

---

## 3. The RDP constraint

Windows App and Devolutions RDM are confirmed primary targets, and they are the one
case where the "Unicode typing solves everything" claim in section 1 does not
automatically hold.

An RDP client does not consume text — it translates local key events into **scancodes**
and forwards them to the remote Windows machine. Our default approach posts a
`CGEvent` with `virtualKey: 0` and the character carried as a Unicode payload. A
client that reads `NSEvent.characters` will see the text and forward it correctly.
A client that reads `NSEvent.keyCode` to build a scancode will see key 0 and send
garbage, or nothing.

### ANSWERED — Unicode mode is unusable over RDP

Tested in **Windows App**, **Devolutions RDM** and **Omnissa Horizon**. All three
behave identically, so this is a property of RDP-style clients, not a per-product
quirk.

**Unicode mode returned 53 letter `a`s for a 53-character string.** The clients read
`NSEvent.keyCode` and ignore the unicode payload entirely — and virtual key 0, which
we pass when carrying text as a payload, *is* `kVK_ANSI_A`. The text does not arrive
mangled; it never arrives at all.

**Virtual-key mode is therefore mandatory for remote targets**, and the first run
exposed two further defects, both since fixed:

| expected | first vk run | cause |
|---|---|---|
| `Hello123` | `hello123` | shift ignored |
| `test@example.com` | `test2example.com` | `@` is shift+2 |
| `!@#$%^&*` | `12345a78` | shift ignored; `^` fell back to unicode |
| `{}[]` and pipe/backslash | brackets only, shift lost | shift ignored |
| `é ü € ~` | `a a 2 a` | dead keys fell back to unicode |

1. **Modifiers must be posted as real key events.** Setting `CGEvent.flags` on the
   character event is enough for native Mac apps, but RDP clients derive modifier
   state from actual Shift/Option key-down/key-up events. Fixed by pressing the
   modifier keys around each character, with a configurable `--mod-delay`.
2. **The unicode fallback was actively harmful** — it silently produced `a`. In
   remote mode there is no fallback: an unproducible character is skipped and
   reported. A password typed wrongly in silence is worse than one typed short.
3. **Dead keys are now composed** rather than skipped, which is what makes the
   quotes, `^`, `~`, `é` and `ü` reachable at all. Reachable characters went from
   196 to **239**.

### The dead-key detail that cost the most time

`UCKeyTranslate`'s `deadKeyState` packs two fields into one `UInt32`. **Only the low
16 bits say a dead key is still pending**; the high word remembers which dead key was
last consumed, so a *successful* composition reports e.g. `0x40000`, not `0`.

Getting this wrong shipped a real bug rather than a theoretical one. On U.S.
International the double quote can be produced by shift+apostrophe then apostrophe,
and `UCKeyTranslate` duly reports the correct character — but that pairing leaves
acute pending, which is then flushed into the *next* character and swallows the
following space. A quoted word plus a quoted letter came out with stray apostrophes
scattered through it and the spaces eaten. Requiring `state & 0xFFFF == 0` makes the
map choose dead-key-then-**space** instead, which is what a person would actually
type.

Also: only genuine character-producing keycodes may serve as the second key. A
modifier keycode "flushes" the accent as far as `UCKeyTranslate` is concerned, so the
naive version picked Right Command (keycode 54) as the completion for the double
quote.

### The layout is not ours to choose — confirmed on the remote

Second RDP run, with modifiers and dead-key composition fixed. Everything in US
positions came through correctly (`test@example.com`, `{}[]`, pipe, backslash,
`!@#$%^&*`), but stray spaces appeared and the accents came apart:

| expected | got | what the remote did |
|---|---|---|
| `"quoted"` | `" quoted"` | typed the quote directly, then our space as a space |
| `'x'` | `' x'` | same |
| `é` | `'e` | apostrophe, then `e` |
| `ü` | `"u` | quote, then `u` |
| `^&*` | `^ &*` | circumflex, then our space |
| `€` | *nothing* | not on the remote layout at all |

One cause for all of it: **the remote is not on U.S. International.** We send
dead-key-then-space; there those are ordinary keys, so the character lands
immediately and our space lands as a space. That US positions all survived proves the
remote is a US-*position* layout — a Dutch or AZERTY remote would have scrambled the
punctuation — so it is plain **U.S.**

`--layout <input-source-id>` now selects which layout to map against, and
`--list-layouts` prints the installed ids. `TISCreateInputSourceList(filter, true)`
includes layouts that are not enabled locally, which matters: nobody enables the
remote's layout on their Mac just to type into it.

**But selecting `com.apple.keylayout.US` is not sufficient on its own.** The macOS US
layout puts accents on option-key dead keys (`option+e` then `e` gives `é`); Windows
US has no such thing, and Alt over there is a menu accelerator. Mapping against
macOS-US alone would therefore emit option combinations that mistype silently on the
remote. `--no-option` drops every Option combination, which is what a Windows target
actually accepts:

- against `U.S. International – PC` (the Mac's own): 239 reachable, via dead keys
- against `U.S.`: 241 reachable, but `é`/`ü` only through macOS-only option dead keys
- against `U.S.` **with `--no-option`: 113 reachable** — full printable ASCII, no
  compositions, and `é ü €` correctly reported as not producible

113 is the honest number for a Windows US remote. Those three characters cannot be
typed there by any keystroke sequence, and saying so beats guessing.

**Design consequence:** the "which layout" setting from the previous section needs a
companion "target is Windows" flag, or better, a single **target profile** — layout
plus option-allowed plus fallback-allowed — chosen per destination app. Local Mac
targets and RDP targets want opposite settings, so this cannot be one global switch.

### Consequence for the design

Both modes now produce byte-identical output in TextEdit, so **virtual-key mode is
the single primary path** — it works locally *and* remotely. That collapses the
two-mode design into one engine with one switch:

- **Default:** virtual keys, with unicode as a per-character fallback for anything
  the layout cannot produce.
- **Remote mode:** the same, with the unicode fallback **disabled** and unproducible
  characters reported instead of guessed.

The layout-mismatch caveat still stands and no local code can fix it: we map using
the Mac's layout, the remote machine re-maps with its own. Phase 3 should let the
user pick which layout to map against, rather than always using the active one.

### VERIFIED over RDP — the typing path is settled

With the remote layout selected and Option combinations disabled:

```sh
./.build/debug/typespike --wait 5 --layout com.apple.keylayout.US --no-option
```

the remote console received exactly:

```
Hello123 test@example.com "quoted" 'x'    !@#$%^&* {}[]|\ ~end~
```

Every earlier defect is gone: no stray spaces, capitals and `@` intact, quotes whole,
`^` and `~` correct. The four spaces where `é ü €` were are the spaces that separated
them — those three were correctly *skipped and reported* rather than guessed.

**It also explains the one character that went missing in the previous round.** An
apostrophe had been dropped from `'x'`, which looked like a timing problem and was
not: raising `--mod-delay` to 30 changed nothing. The cause was the dead-key
composition itself — sending "dead key, then space" to a machine that has no dead
keys. Mapping against the remote's own layout removes the composition entirely for
`'` and `"`, and the problem disappears with it. Timing was never involved.

These exact settings are what `TargetProfile.windowsRemote` carries, applied
automatically when Windows App, Devolutions RDM, Omnissa Horizon or VMware Fusion is
the target app.

## 4. MVP definition of done

Press ⌃⌥V anywhere → the panel appears → click an item → the panel closes, the
previously focused app comes forward, and the text is typed into it character by
character. Moving the mouse aborts mid-type. History survives a restart.

Everything else — the neon styling, settings, masking heuristics — is finetuning
on top of that.

---

## Phase 0 — Scaffold and build pipeline

*Goal: `make run` puts a working menu-bar icon on screen. Rough size: small.*

- [x] ~~`git init`, `.gitignore`~~ — **dropped.** This stays a plain local folder;
      no version control. Generated output lives in `.build/` and `dist/`.
- [x] `Package.swift` — executable target, macOS 14 platform, Swift 5 language mode
- [x] `Resources/Info.plist` — `LSUIElement = 1` (no Dock icon), bundle ID, version
- [x] `scripts/bundle.sh` — `swift build -c release`, assemble
      `dist/Toothpaste.app/Contents/{MacOS,Resources}`, copy binary + Info.plist,
      `codesign`
- [x] `Makefile` — `build` / `app` / `run` / `clean`
- [x] `main.swift` + `AppDelegate.swift` — `NSApplication`, activation policy
      `.accessory`, `NSStatusItem` with a menu containing only *Quit*
- [x] **Self-signed cert** — *your action*: create `Toothpaste Dev` in Keychain
      Access (steps in README.md). `bundle.sh` already looks for it and warns when
      it is missing.

**Checkpoint:** `make run` → icon in the menu bar, no Dock icon, Quit works.
This de-risks the whole no-Xcode build path before any real code exists.

**Result: passed.** SwiftPM builds and links against AppKit with CLT only — no
Xcode needed. `dist/Toothpaste.app` is **88 KB**, runs as an accessory process, and
does not appear in the Dock. Ad-hoc signed for now, pending the certificate.

---

## Phase 1 — MVP: watch, store, type

*Goal: the definition of done above. Functional, deliberately ugly. Rough size: the bulk of the work.*

### 1a. Model and storage — **done**
- [x] `ClipItem` — id, text, timestamp, pinned, concealed. `(19)` in the reference
      screenshots is the character count; `characterCount` provides it.
- [x] `HistoryStore` — `@MainActor` observable; newest first, pinned items pinned
      to the top, dedupe by text (an existing entry moves up instead of doubling),
      cap at 50
- [x] Persistence — `Codable` JSON at
      `~/Library/Application Support/com.michaelsmith.toothpaste/history.json`,
      debounced writes. **Concealed items are held in memory only and never written.**

### 1b. Clipboard watching — **done**
- [x] `ClipboardWatcher` — 300 ms timer on `NSPasteboard.general.changeCount`
- [x] Read `.string`; skip empty/whitespace-only
- [x] Skip `org.nspasteboard.TransientType` and `AutoGeneratedType` entirely
- [x] Mark `org.nspasteboard.ConcealedType` items as concealed

**Verified end-to-end** (no permissions needed — drive it with `pbcopy`, read
`history.json`): capture works, dedupe moves the repeat to the top without
duplicating, whitespace-only is skipped, newlines survive the round trip, and a
pasteboard item flagged `ConcealedType` never reaches the file.

### 1c. Typing engine — the core

**Spike first (see section 3).** Before anything else in this phase:

- [x] Throwaway binary that types `Hello123 é@#` after a 3 s countdown, switchable
      between Unicode mode and virtual-key mode
- [x] Run it against TextEdit, **Windows App**, and **Devolutions RDM**
- [x] Also try each client's own keyboard-mode setting — if Unicode mode works once
      the client is set to Unicode keyboard input, virtual-key mode may not be needed
      at all, which removes a lot of code
- [x] Record the result here; it decides how much of the rest of 1c gets built

Then:

- [x] `Accessibility.swift` — `AXIsProcessTrustedWithOptions` check + prompt;
      block typing and show why when not trusted
- [x] `TypingEngine`, Unicode mode — per character:
      `CGEvent(keyboardEventSource:virtualKey:0:keyDown:)`, `keyboardSetUnicodeString`,
      `flags = []`, post to `.cghidEventTap`, then the keyDown/keyUp pair
- [x] `TypingEngine`, virtual-key mode — build a reverse character→(keycode, modifiers)
      map once from the active `TISInputSource` via `UCKeyTranslate`; fall back to
      Unicode mode for anything unmappable. **Only if the spike says it is needed.**
- [x] Split on newlines, post a real Return (vk 36) between segments
- [x] Configurable initial delay (default 100 ms) and per-character delay
      (fast 3 ms / med 10 ms / slow 25 ms / **remote 60 ms**)
- [x] Wait for the hotkey's modifiers to be physically released before starting
- [x] Cancel when `NSEvent.mouseLocation` moves more than 80 pt from its start

### 1d. Focus handling
- [x] `FocusRestore` — capture `NSWorkspace.shared.frontmostApplication` *before*
      showing the panel; `activate()` it on paste, wait for the activation to
      settle, then type
- [x] Verify against Windows App and RDM that reactivating the client leaves the
      remote-side caret where it was. If it does not, the phase 4 overlay moves here.

### 1e. Minimal panel — **built, hotkey unverified**

> The panel opens, renders and lists history (verified by capturing the window by
> id). **Pressing ⌃⌥V could not be verified from here:** Carbon hotkeys are matched
> by the WindowServer ahead of injected events, so synthetic `CGEvent`s never reach
> them — confirmed with a standalone test program that registers successfully
> (`status=0`) and still never fires on a synthetic press. It needs a human finger.
> A left-click on the menu bar icon opens the panel too, which is better UX anyway
> and gives a path that does not depend on the hotkey.

- [x] `PanelController` — borderless `NSPanel`, `.floating` level, visible on all
      spaces, `canBecomeKey` overridden
- [x] `PanelView` — search field + plain list of items; click a row to paste
- [x] `Hotkey` — Carbon `RegisterEventHotKey` for ⌃⌥V, toggles the panel
      (Carbon, not `NSEvent` monitors: it works without Accessibility and can
      actually consume the keystroke)
- [x] ESC and click-outside dismiss the panel

**Checkpoint:** the manual test matrix in section 5.

---

### Where the app runs from is not a detail — it decided the permission

The Accessibility grant refused to stick for a long stretch, through a certificate
fix and two `tccutil reset` cycles. The signature was never the remaining problem:
`codesign --verify --strict` passed and the running binary satisfied its designated
requirement throughout.

The cause was that the app was being run from **`dist/Toothpaste.app`**, which
`make app` deletes with `rm -rf` and rebuilds on every single build — inside a
Nextcloud-synced folder. A stable code signature is not enough when the bundle the
grant points at keeps being destroyed and recreated underneath TCC.

Fix, in two parts:

1. **`make install`** copies the signed app to `~/Applications/Toothpaste.app` with
   `ditto` (which preserves the signature) and runs it from there. Build output stays
   disposable; the granted app sits somewhere stable. Confirmed: the orange
   "no Accessibility permission" banner disappeared and stayed gone.
2. **`install.sh` updates in place** rather than removing the destination first. The
   first version did `rm -rf` on the destination, which reproduced exactly the
   problem it was meant to solve. Overwriting with `ditto` while the `.app` directory
   itself keeps existing preserves the grant across reinstalls — verified by
   reinstalling and finding the permission still in force.

`make reset-permission` clears a stuck grant for this bundle id only, for when the
entry is already poisoned.

**Guard on deletion.** The three `rm -rf` sites (bundle assembly, install, clean) now
route through a `remove_bundle` helper that refuses anything which is not an absolute
path ending in `Toothpaste.app`. Verified that empty string, `/Applications`, `$HOME`
and `/` are all rejected.

## Phase 1 — CLOSED except one safety question

Everything in the acceptance list below passes, including the two behaviour changes
made after it was written: choosing an item arms it and the destination is the window
you click next, and Esc cancels typing — confirmed working inside an RDP session, not
just locally.

Two things still outstanding, both listed under *Known unknowns*: Secure Input Mode,
and whether a password manager's clipboard entry is recognised as concealed.

**A tooling mistake worth remembering.** `scripts/verify-capture.sh` used to `rm -f`
the history file so it could assert on counts. That was harmless while the history
held only test data and destroyed a real one the first time it ran in anger. It now
moves the file aside and restores it via an `EXIT` trap, so an interrupted or failing
run still puts it back. A script that is only safe on an empty machine is not a safe
script.

## Phase 1 acceptance — the detail

Verified already: clipboard capture and dedupe (`make verify`), the typing engine over
RDP, ⌃⌥V firing, the panel opening and rendering, and focus restore naming the correct
previous app.

Everything below needs a human, in roughly this order. Anything that fails here is a
phase 1 bug, not phase 2 polish.

**Accessibility is now granted and holding** (see the section above — the grant only
stuck once the app was run from `~/Applications` instead of `dist/`). These are the
tests that were waiting on it:

- [x] Paste into a plain Mac app end to end: ⌃⌥V → click a row → text appears
- [x] Paste into an RDP session, and confirm the header flips to
      `Windows via RDP (auto)` on its own
- [x] Multi-line clipboard text — do the Returns land as Returns?
- [~] Mouse-move cancellation — **removed by decision.** It fired during ordinary
      use; Esc is the cancel now, and it works from inside an RDP session.
- [x] A string containing characters the remote layout lacks — the menu bar glyph
      should flip to ⚠️ with a tooltip naming them

**Panel behaviour, no permission needed — automated and passing.**

Driven with synthetic key and mouse events, which reach a normal app fine; only
Carbon hotkeys are unreachable that way.

- [x] Search field receives keystrokes — typing `mod` filtered 23 items to 3 and the
      footer followed. This was the one part of the `canBecomeKey` / non-activating
      trade-off that could have failed quietly, and it does not.
- [x] ↑/↓ move the selection — two presses moved the highlight to the third row
- [x] ESC closes
- [x] Dragging by the header moves the panel — (1100,495) → (940,405), exactly the
      offset dragged — and reopening restored (940,405)
- [x] History survives quitting and relaunching — entries three hours old outlived
      roughly ten rebuild-and-relaunch cycles during the session
- [x] ⏎ pastes the selection — needs Accessibility
- [~] Clicking outside closes — **removed by decision.** It contradicted keeping the
      panel visible after delivery. Esc, the hotkey, or the menu bar item close it.
- [x] Dragging inside the search field selects text rather than moving the window
- [x] Default position is the bottom-right corner of whichever screen the mouse is
      on, 16pt in, clear of the menu bar and Dock

**Known unknowns from section 3 — resolved:**

- [x] **Secure Input Mode does not block us.** Typing works into real password fields,
      both native UI fields and Terminal. This was expected to fail, and the plan
      allowed for building a warning around a silent failure — none of that is needed.
      Worth stating in both directions: it is why the tool is useful for credentials,
      and it is the clearest evidence that this is functionally an autotyper.
- [x] **A password manager's clipboard entry shows as dots and never reaches disk** —
      verified 2026-09-09 against the real thing, not a simulated pasteboard item.
      `scripts/inspect-pasteboard.swift` reports the type markers a source sets while
      deliberately never printing content, so it can be run while copying real
      passwords.
      - **1Password** sets `org.nspasteboard.ConcealedType` plus its own
        `com.agilebits.onepassword`.
      - **Bitwarden** sets the convention type and nothing else of its own.
      - Ordinary text — including text copied out of an RDP session, which arrives
        carrying `com.devolutions.rdp.*` types — carries no marker, as it should.
      - Both appear as dots in the panel with an eye button to reveal, and neither
        reaches `history.json`. Since only pinned entries are persisted at all, a
        concealed item would have to be pinned to even be a candidate, and it is
        excluded there too.

      **Noted while verifying:** the mask draws one dot per character (capped at 20),
      so the length of a password is visible over someone's shoulder. That is weak
      information, and it does make two different secrets tellable apart in the list.
      Left as is; a fixed-width mask is a one-line change if the trade is judged the
      other way.

## Phase 2 — The look — **DEFERRED by decision (2026-09-08)**

> Dropped from the near-term plan. The panel stays plain and functional; styling
> waits until the tool actually works well. Phase 3 is the real next step, because
> the profile system that came out of the RDP work is what makes this usable, and
> appearance is not.
>
> Kept below for whenever it is wanted.

*Goal: match the reference screenshots. Rough size: medium, mostly mechanical.*

- [·] `Theme.swift` — near-black surface `#0d0d0f`, raised rows `#18181b`, magenta
      accent, monospace throughout, dim gray secondary text
- [·] Header — `TOOTHPASTE` letterspaced in accent, `// clipboard history`
      subtitle, hotkey hint on the right, gear button
- [·] Search field styled as `> search ...`
- [·] `[clear all]` pill
- [·] Item rows — rounded card, mono text, right-aligned `(19) 44m ago` metadata,
      three square action buttons: **pin**, **delete**, **reveal**; hovered/active
      button gets the magenta outline
- [·] Relative timestamps (`44m ago`, `1h ago`)
- [·] Footer — `:: 3/50 items` above a hairline separator
- [·] Basic masking — concealed items render as dots; the eye button reveals
      temporarily
- [·] Keyboard navigation: ↑/↓ through results, ⏎ to paste the selection

---

## Delivery model changed: arm, then click the destination

Originally the panel hid on click and typed into whatever was frontmost before it
opened, using `FocusRestore`. That is the wrong target the moment you want a specific
field — particularly inside a remote session, where the caret position is decided by
where you click on the remote side.

Now: choosing an item **arms** it. The panel stays open with an accent banner reading
*"now click the field you want this typed into"*, the chosen row is outlined, and the
next click in any other application decides the destination. Esc cancels.

Mechanically this rides on the existing global mouse-down monitor, which only ever
sees events delivered to *other* applications — so a click inside the panel does not
trigger it, and a click anywhere else does. `PanelController.onOutsideClick` swaps
between "dismiss" and "deliver here" depending on whether something is armed.

After the click, `waitForDestination()` polls until a non-Toothpaste app is frontmost
before typing, and the profile is then chosen from *that* app rather than the one the
panel was opened over. `FocusRestore` survives only to label the header, which now
reads `from <app>` rather than `→ <app>`, because it names where you came from and no
longer the destination.

**Initial delay.** `TargetProfile` gained `initialDelayMs`, waited once before the
first character: 50 ms locally, 200 ms for remote sessions. Without it the first
character was intermittently swallowed, because a freshly clicked window has focus
before it is ready to take keyboard input — and the character that gets lost is the
first one, which in a password is as damaging as any other.

## Done since phase 1 closed

- **Start at login** — `SMAppService.mainApp`, toggled from the menu. A clipboard
  manager that is not running captures nothing, so every reboot otherwise left a hole
  in the history. The menu reflects `requiresApproval` too, because a decision made in
  System Settings wins over ours.
- **`load()` no longer overwrites what it could not read.** A missing file is a normal
  first run; a file that exists but fails to decode is moved to
  `history.unreadable-<timestamp>.json` before anything else is written. Verified by
  feeding it invalid JSON: the damaged file survived intact alongside a fresh one.
- **App icon** — `scripts/make-icon.sh` renders `Resources/Toothpaste.icns` from the
  same emoji the menu bar uses, so the two cannot drift apart.
- **One app, not two.** `dist/Toothpaste.app` was registering with LaunchServices
  alongside the installed copy, so the app appeared twice in Launchpad. `install.sh`
  now unregisters the build copy.

## Decisions taken 2026-09-08, after phase 3

**History at rest: session-only, with pinning as the opt-in to persistence.**

Superseded the auto-forget decision below within the hour. Nothing unpinned is written
to disk at all — a restart leaves only pinned entries. This is simpler and stronger
than an age limit, because the common case (copied something, used it, moved on) never
reaches the file in the first place. Concealed items are excluded even when pinned.

The age limit stayed, now scoped to a running session: with launch-at-login the app can
be up for weeks, so "forget after 8 hours" still limits what is in memory.

Verified by `make verify`: nothing unpinned reaches the file, a concealed item never
does, a pinned entry survives a restart, and a copy made after that restart is not
added to the file.

**The clear button confirms itself.** One click changes it to *sure?*, a second clears.
No alert — that would activate the app and the panel is deliberately non-activating —
and no second button to mis-click. It disarms after three seconds so a forgotten click
cannot be completed by an unrelated one later. Pinned entries are not cleared.

**Earlier, superseded: auto-forget, not encryption.** The stored history had grown real
work content, so the options weighed were: leave it, mask by heuristic, encrypt with a
Keychain key, or expire on a timer. Expiry won — it limits how much is on disk at any
moment without making the file undebuggable, and without a heuristic that would
sometimes miss and sometimes over-reach.

- `Settings.retentionHours` — never / 1 / 4 / 8 / 24 hours / 1 week, in General
- Runs at launch, on a 60-second timer, and immediately when the setting changes. A
  timer as well as launch, because an entry ageing past the limit while the app sits
  idle should go then, not whenever it next restarts.
- **Pinned entries survive expiry**, exactly as they survive the clear button.
  Pinning is a deliberate "keep this".
- **Defaults to never.** Anything destructive that arrives switched on would delete
  whatever was already stored, without being asked.

Verified with seeded entries at 0.2h, 5h, 9h (pinned) and 48h against a one-hour
limit: the recent one and the pinned one survived, the other two went.

**Hotkey stays fixed at ⌃⌥V.** A recorder is real work — capturing a chord without
passing it through to other apps is the awkward part — and the current binding
conflicts with nothing. The settings window says it is not configurable rather than
showing a control that does nothing.

**Phase 2 styling stays parked.** Function over appearance, confirmed a second time
now that the functionality is complete.

**`clear all` is now `clear`, with confirmation.** It asks in the footer rather than
in an alert, because a system dialog would activate the app and the panel is
deliberately non-activating. Pinned entries are excluded and the prompt says how many
are being kept. Esc backs out of the confirmation before it closes the panel, so
there is no state where you are unsure whether anything was cleared.

## From a day of real use — 2026-09-09

**The search field is gone until you type.** It was taking up permanent space for
something used rarely. Typing any printable character brings it up; Esc clears it and
puts it away again, before Esc gets to closing the panel.

Two obvious approaches failed first, both worth recording because they look right:

1. **Intercept the first keystroke and seed a real `TextField` with it.** That
   character disappears. A text field selects its contents when it takes focus, so the
   *second* keystroke replaces the first — typing `ser` produced `er`. The bug is
   invisible unless you type more than one character.
2. **Keep the field present but zero-height.** The test showed every keystroke lost —
   but that test was invalid: someone was typing in another window at the time, so
   the synthetic keystrokes went there rather than to the panel. Whether a zero-height
   field can hold focus is therefore **unknown**, not disproven. Left untested because
   the approach below already works; worth revisiting if search ever needs ⌘V or
   cursor movement.

What works, and is tested, is not using a text field at all. The panel takes focus itself
(`.focusable()`), collects printable characters into a plain string, and handles
backspace. Control codes sit below `0x20` and the arrow and function keys in the
private-use range from `0xF700`, so guarding on that range leaves the existing
arrow/Return/Esc handlers untouched.

The cost is real and accepted: no selection or cursor movement inside the query, and no
⌘V into it. Fair for something you type three characters into; revisit if the search
ever becomes load-bearing.

**Checked while here: does an open panel swallow typing meant for other apps?** It
collects loose keystrokes and stays open, so this was worth proving rather than
assuming. It does not.

| how you leave the panel | keystrokes go to |
|---|---|
| clicking another window | that window — correct |
| ⌘Tab | the app switched to — correct |
| AppleScript `activate` | **the panel** — but no one switches apps that way |

The AppleScript case briefly looked like a serious bug and was an artifact of the test
method. Programmatic activation does not move key focus off a floating non-activating
panel the way a click or ⌘Tab does.


**The header named a stale app, and with it the wrong profile.** `FocusRestore`
captured the frontmost application once, when the panel appeared. That was sound while
the panel was transient — it closed the moment you chose something, so one snapshot
could not go stale. Making the panel stay open invalidated the assumption without
anyone noticing: activate another window while the panel is up and the name froze on
whatever was there before.

Worse than the name was the profile printed beside it, computed for that stale app. You
could be looking at `Mac apps` while a click into Windows App would use
`Windows via RDP`. Wrong precisely when it mattered — when switching apps, which is the
only time you would read it.

Replaced by `FrontmostWatcher`, which follows `NSWorkspace.didActivateApplication`.
Because our panel is a non-activating window, activating it does not make Toothpaste
frontmost, so the tracked app keeps pointing at the real destination. The label went
back to `→ App · Profile`, since it now genuinely names where the text will go.

A just-happened message ("typed 42 characters into X") is held for six seconds so live
tracking cannot wipe it the instant you click elsewhere.

`FocusRestore.restore()` had been dead since delivery moved to `waitForDestination()`;
the whole type is gone rather than left lying around.


Three things surfaced that no amount of planning would have:

**Esc did not unwind one step at a time.** With an item armed, Esc closed the panel
rather than cancelling the choice — the same guard existed for the clear confirmation
but not for arming. Esc now walks back: clear confirmation, then armed item, then the
panel. Leaving someone unsure whether their choice is still waiting for a destination
is worse than an extra keypress.

**The whole panel was a drag surface.** `isMovableByWindowBackground` moves the window
from anywhere that is not an active control, so brushing past a row shifted it.

The first fix was wrong and worth recording: making the header a drag handle with a
background `NSView` that calls `performDrag` does nothing, because SwiftUI does not
draw its text as separate views, so that view never receives the click. The mechanism
AppKit actually offers is `mouseDownCanMoveWindow`, asked of the view under the
pointer. So the window stays draggable everywhere and `WindowDragBlocker` sits under
everything below the header. Verified: row and search field do not move it, header
moves it exactly as far as dragged.

**Pinned rows and the keyboard selection were fighting over the same colour.** The
accent background already means "Return acts on this one" and moves with the arrow
keys, so painting pinned rows in it would have made two different states identical.
Instead: pinned gets a left accent stripe, a slightly lighter fill and an accent pin
icon; selection keeps the accent background. Both can be true at once and stay
tellable apart.

The related complaint was that the top row looked chosen on open when nothing had been.
The selection is now optional and starts empty — it appears once you search or use the
arrows. Return with nothing selected still takes the top row, which is what you mean
after typing a search.

**Character counts and timestamps are gone from the rows.** They were carried over from
the 0xpaste screenshots without asking whether they earned their place. They did not —
the rows are now the text and its three buttons.

## Dragging, verified across displays — 2026-09-09

Driven with the mouse across all three displays in one continuous drag. The window held
the grab offset exactly for the whole tour, and stayed put afterwards.

**Two false alarms, both human input rather than the code.** A panel that appeared to jump
back to its old position had been dragged there by hand; a set of keystrokes that
seemed to vanish had gone to a window that was being typed in. On a machine
someone is actively using, an unexplained state change is more likely to be them than a
bug — worth suspecting before going looking in the code.

**Open, and a real choice:** the panel can be dragged mostly off-screen and is
remembered there. `isUsable` only requires 120×80 points of overlap on reopen, so a
panel nudged 260 points below the screen edge comes back 260 points below the screen
edge. Defensible — it is where it was put — but a panel dragged off by accident is
then hard to find again. Clamping on reopen would fix that at the cost of no longer
being able to park it half off deliberately.

## 1.1.0 — 2026-09-15

First release after other people started using it, which changes the standard: removals
now cost someone their habits, so they need a better reason than "it did not earn its
place". The hover detail strip had one.

- Removed the detail strip (see above). Nothing replaces it.
- **Command Line Tools 6.4 broke the build**, independently of any change here. It
  ships a macOS 27 SDK whose SwiftUI declares `@State` as a macro without shipping the
  plugin that implements it, so every SwiftUI file fails to compile. Full Xcode has the
  plugin; CLT does not. `scripts/select-sdk.sh` picks the newest SDK that predates the
  macro requirement and returns nothing once the plugin appears, so the workaround
  removes itself. Verified the failure was not ours by building the previous commit:
  58 errors there too.

  Worth noticing for the distribution model: "clone and build" means a toolchain update
  can break every colleague at once, with no bad commit to point at. This is the first
  instance.

## The panel was unreadable in Light Mode — 2026-09-17

Reported by a tester, not found here: on a machine set to the light system theme the
panel came up as a black box with text that was almost invisible against it. The header,
the rows, the footer — all of it near-black on near-black.

**The cause is a split that looks reasonable on each side.** `PanelView` paints its own
surfaces, because a rounded floating panel cannot use the window background. Those were
fixed greys — `Color(white: 0.07)` for the panel, `0.11` and `0.155` for rows, `0.12`
for the search field. The *text*, though, used the semantic colours `.primary`,
`.secondary` and `.tertiary`, which resolve against the window's effective appearance no
matter what the surfaces do. Nothing pinned the panel's appearance, so it inherited the
system theme.

In Dark Mode the semantic colours come out near-white on those near-black fills and the
result looks designed. It was not: the two halves were simply never asked to disagree.
Switch the system to light and the text flips to near-black while the surfaces stay put.

**It survived to a release because every eye on it ran Dark Mode.** There is no compiler
warning, no runtime complaint, and no way to notice from the code — each half is
individually correct. The appearance is a property of the machine, so it only appears
when the app reaches a machine configured differently. This is the first defect here
found by someone other than the author, and it is the kind that only that can find.

**The fix: `Theme.swift`, every colour stating both values.** A dynamic `NSColor` per
colour, bridged into SwiftUI with `Color(nsColor:)`. Resolving through AppKit rather
than reading `\.colorScheme` keeps it out of the views — no environment value has to be
threaded down to a row for it to know which grey it is.

The dark values are the originals, unchanged. The light ones invert the *direction* of
each step while keeping its order, because a raised surface reads as lighter than its
background in dark and darker than it in light:

| | dark | light |
|---|---|---|
| panel surface | 0.07 | 0.98 |
| row | 0.11 | 0.93 |
| pinned row | 0.155 | 0.87 |
| search field | 0.12 | 0.92 |
| border | white @ 0.12 | black @ 0.15 |
| separator | white @ 0.06 | black @ 0.09 |

That inversion is the reason one set of greys cannot serve both, and it is what AppKit's
own control colours do.

**The status colours were wrong in the same way, and measurably so.** `.orange` marks a
missing Accessibility permission and characters that cannot be typed; `.green` confirms
the grant. Against the light panel surface `systemOrange` reaches **2.0:1** and
`systemGreen` **2.0:1** — below readable for text someone has to act on. The light
variants are the same hues taken down to **4.2:1** and **4.8:1**. In dark mode both keep
the system colours. This also covered the settings window and onboarding, which are
otherwise standard controls and adapt by themselves.

**Verified by rendering, not by switching the machine over.** Compiling the real sources
against a throwaway `main.swift` puts `PanelView` in an `NSHostingView` inside an
offscreen window with a chosen `NSAppearance`, and `cacheDisplay` writes it to PNG. Four
states came out — light and dark, idle and armed — with the dark pair confirming the
existing look was untouched. Two things matter if this is done again: the harness must
be named `main.swift`, since top-level code is allowed nowhere else, and `HOME` plus
`CFFIXED_USER_HOME` must point at a scratch directory, because `HistoryStore` saves on a
timer and would otherwise write the harness's mock items over the real `history.json`.

**What this says about the distribution model.** Clone-and-build put the app on machines
that are not this one, and the first thing that came back was not a crash or a typing
failure but a setting nobody here had. Worth assuming there are more: anything read from
the system rather than chosen by the code — appearance, accent colour, keyboard layout,
display count, language — has only ever been tested at one value.

## Versioning — 2026-09-09

Tagged, but **no binary attached to the release**, deliberately: a downloaded `.app`
carries `com.apple.quarantine` and Gatekeeper rejects it, which is the exact problem
clone-and-build was chosen to avoid. A release asset would quietly undo that decision.

The gap worth closing was different. `Info.plist` still said `0.1.0` from phase 0, and
**the version appeared nowhere in the app**. With clone-and-build everyone sits on
whatever commit they last pulled, so when a colleague reports something odd there is no
way to know what they are running — and a version number alone does not identify a
build here. The commit does.

- `Info.plist` → `1.0.0`
- `scripts/bundle.sh` stamps `ToothpasteCommit` from `git rev-parse --short HEAD`,
  appending `+local` when the working tree is dirty
- Settings → General shows `1.0.0 (57aec6b)`, selectable so it can be pasted into a
  message
- Falls back to `unknown` when built without git, so a tarball still builds

## Raised, not yet decided

- [~] **No way to read a long entry before sending it.** A detail strip was built for
      this on 2026-09-09 and **removed again on 2026-09-15**, after a few days of real
      use and once other people had started running the tool. Nothing replaced it.

      It worked, and the two decisions inside it were sound: it appeared only when the
      text would not have fitted anyway, and a masked entry never qualified for one, so
      there was no path by which it could print a secret. It was still removed. Reading
      a long command before sending it turned out to be something wanted rarely, while
      the strip was present on most rows most of the time, and a panel you glance at
      pays for anything permanently on screen.

      The original problem stands and is unsolved: rows are one line and truncate, so a
      300-character command is not fully visible anywhere. If it is picked up again,
      note that hover was the wrong trigger — it fires constantly while you move
      towards the row you actually want. Something deliberate, on a key or a button,
      would not have that problem.

      Auto-scrolling the row was considered at the time and argued against: the job is
      to *verify* a command before it reaches a production machine, and scrolling text
      cannot be read at your own pace, scanned, or looked back at.

## Deferred, deliberately — revisit later

- **`clear all` has no confirmation and takes pinned items with it.** Agreed as
  acceptable for now; worth reconsidering when settings exist.
- **Whether the panel should float above other windows.** It does, because otherwise
  clicking the destination would cover it and "stay visible" would not hold. Accepted
  as the most logical behaviour for now, but flagged as not obviously right.

## Phase 3 — Settings — **built**

A separate window rather than something inside the panel: the profile editor needs
room, and the panel is deliberately small and transient. Reached from the menu bar
item's right-click menu, or ⌘, once the window has focus.

**General**
- [x] Max history — 10/25/50/75, applied to the store immediately
- [x] Start at login, reflecting `requiresApproval` as well as on/off
- [x] Accessibility status with a button through to System Settings
- [x] **Hotkey recorder** — built 2026-09-09. Click the combination in Settings, press
      a new one, done. `reset` puts ⌃⌥V back.

      **It was easier than I claimed.** I had called it "middling work, and capturing a
      chord without passing it through is the awkward part". That is true of a *global*
      recorder; this one lives in the settings window where the app has real focus, so
      a **local** `NSEvent` monitor returning nil consumes the keystroke. That is what
      stops ⌘Q from quitting the app while you are trying to record it.

      - At least one of ⌘, ⌃ or ⌥ is required. Shift alone would turn an ordinary
        capital letter into a global shortcut and swallow it everywhere.
      - Registration can fail because another app holds the combination. The old
        shortcut is restored and the window says so, rather than leaving a dead key.
      - The displayed key comes from the active layout via `UCKeyTranslate`, since
        which character a keycode produces is layout-dependent.

      The recorder shows a message only when the button cannot say it itself. A "now
      ⌃⌥B" confirmation was there first and simply repeated the button, which had
      already changed to ⌃⌥B — spotted in use, not in review.

      Verified: a valid combination is captured and applied; a shift-only
      attempt is refused with the reason and recording continues; reset restores the
      default; all of it persists.

      A newly registered shortcut **does** fire — confirmed with a real keypress, which
      is the only way: Carbon hotkeys do not respond to synthetic
      events (see phase 1e).

      **Still unverified**: the "already taken by another app" path, which needs a
      combination genuinely held by something else.

**Typing profiles** — the part the RDP work made necessary
- [x] Add, remove, rename, reset to defaults; persisted as JSON in `UserDefaults`
- [x] Keyboard layout picker over `KeyboardLayout.installedLayouts()`, including
      "this Mac's active layout" for the local case
- [x] Allow Option, allow Unicode fallback — each with a line saying *why* you would
      turn it off, because both are wrong-by-default for remote targets and the
      reason is not guessable
- [x] Initial / per-character / around-modifier delays as **number fields with
      steppers**, not sliders. Sliders were tried first and were wrong twice over:
      SwiftUI draws one tick per `step`, so three fields with different steps drew 50,
      100 and 20 ticks and looked nothing like each other — and more importantly, a
      slider can neither set nor show an exact value. These are numbers you reproduce
      and compare ("modifier delay 30 fixed it"). The three also have genuinely
      different useful ranges, so no single slider scale serves all three without
      being either inconsistent or too coarse where precision matters.
- [x] Which apps a profile claims, added by **picking the app** rather than typing a
      reverse-DNS identifier

**Layout check** — the reason this phase was worth doing
- [x] Pick a profile, paste any text, and see exactly which characters that layout
      cannot produce *before* typing it into a remote machine. This is the
      `--dump-map` diagnostic made answerable by anyone, and it answers the question
      that actually matters: will my password arrive intact?
- [x] Warns when a profile still allows the Unicode fallback, since that turns
      "skipped" into "silently typed as the letter a" over RDP

**Fixed while building it:** the layout map was being constructed in a computed
property, so every keystroke in the sample field triggered several thousand
`UCKeyTranslate` calls. It is now built once per layout choice.

### Where settings live, and why — decided 2026-09-08

Settings sit in their own window, not inside the panel, with one exception.

0xpaste puts its settings in the panel, and that works because it has seven simple
switches. Ours is a different scale: several profiles, each with a layout, three
delays, two consequential toggles and a list of apps, plus the layout check with an
input field and a result area.

The stronger reason is technical. The panel is deliberately a **non-activating**
window — it must not take focus, or "choose first, then click the destination" stops
working. Settings want the opposite: real focus for text fields, pickers, and the
file panel behind *Add app…*, which activates the app. Putting both in one window
would mean flipping the panel between two focus models depending on what it is
showing, which is exactly the kind of hidden state that produces bugs later.

The exception is the **profile override**, which is now a menu in the panel header
next to a gear that opens the window. It is the only setting reached often — the rest
is configured once per destination and then left alone. It was previously buried in
the right-click menu.

The first version of the window was 520 points wide, which left the editor about 290
across: field labels wrapped onto two lines and the sliders shrank to thumbnails. Now
760 and resizable.

## Phase 4 — Polish and hardening

*Goal: the things the MVP deliberately skipped. Pick from this list rather than doing all of it.*

- [~] **Click-to-target overlay** — **not needed.** Arming an item and letting the
      next click choose the destination gets the same result without an overlay.
      Original sketch: transparent fullscreen window, capture the
      click point, synthetic click, then type. Only if phase 1's focus restore
      proves insufficient for your actual targets.
- [~] **Password heuristics** — **not chosen.** Session-only history solved the same
      worry without a detector that would miss some and over-reach on others.
      Original sketch: mask entries that look like secrets even when the
      source app did not mark them (length + charset entropy, `sk-`/`ghp_`-style
      prefixes, adjacency to a password manager being frontmost)
- [x] Multi-display placement
- [x] "Copy to clipboard" as a secondary row action — note this re-introduces the
      feedback loop the MVP avoids by never writing to the pasteboard; mark our
      own writes so the watcher ignores them
- [x] **Onboarding for the Accessibility grant** — built 2026-09-09. A window on first
      launch when the permission is missing, also reachable from the menu bar item, and
      shown again if the grant ever disappears. It states plainly that the failure is
      *silent*, links straight to the settings pane, names and reveals the exact bundle
      the grant applies to, and confirms itself the moment the switch is flipped —
      `AXIsProcessTrusted` has no notification, so it polls every two seconds.

      Once granted, the same window becomes a short "how it works": arm an item, click
      the destination, Esc cancels, nothing unpinned is stored.

      Two debug flags kept deliberately: `--debug-ungranted` renders the not-yet-granted
      state on a machine where the permission is already in place, and
      `--debug-onboarding` opens the window when nothing is wrong. The alternative for
      checking that screen is `tccutil reset`, which costs a real re-grant.

### Correction: the grant follows the signature, not the path

While testing the above, the `dist/` copy — never explicitly granted — turned out to be
trusted. The reason:

```
designated => identifier "com.michaelsmith.toothpaste" and certificate leaf = H"f5d3…"
```

No path. `codesign --verify -R` confirms each copy satisfies the other's requirement,
so TCC sees one app, and deleting and recreating a bundle is irrelevant.

**So yesterday's diagnosis was over-determined.** Two things changed at once — a stable
signing certificate *and* moving the app to `~/Applications` — and the success was
credited to both. Only the certificate was doing the work. The earlier claim that "a
stable signature is not enough if the bundle keeps being deleted" was wrong, and it is
now corrected in `CLAUDE.md`, `README.md` and `scripts/install.sh`.

Installing to `~/Applications` is still the right default, for reasons that survive:
launch-at-login registers a path that `make app` deletes, two registered copies appear
twice in Launchpad, and the project folder is Nextcloud-synced.

- [~] ~~Onboarding screen for the Accessibility grant, with a deep link to the right~~
      System Settings pane
- [x] README with screenshots
- [x] **Distribution: clone and build** — settled 2026-09-09. Private repo at
      `github.com/erymantho/mac-toothpaste`; colleagues clone, `make cert`,
      `make install`.

      **Quarantine decides this, not signing.** A downloaded app carries
      `com.apple.quarantine` and Gatekeeper rejects anything not notarised by Apple,
      which needs a paid developer account. A locally built app is never quarantined
      and simply runs — verified: our build carries only `com.apple.provenance`.
      Building also means each person's certificate is their own, so nobody's
      permission depends on someone else's certificate not expiring. Mine expires
      2027-09-08.

      **A test that proved nothing, and why.** `spctl -a` reported "accepted" even for
      a freshly quarantined copy — because Gatekeeper assessment is *disabled* on this
      machine (`spctl --status` → assessments disabled). On a colleague's Mac, with it
      enabled by default, the same app is blocked. Check the machine's own posture
      before drawing conclusions from a security test run on it.

      `make cert` was added so nobody has to do the Keychain Access dance: it generates
      an RSA key and a self-signed code-signing certificate with openssl, imports it
      with `-T /usr/bin/codesign` so builds do not prompt, and **refuses to create a
      second one with the same name** — duplicates are what made the Accessibility
      grant reset at random. Ten-year validity, against Keychain Access's default of
      one.

      Not chosen, and why: **DMG** puts every colleague through the Gatekeeper override
      in System Settings on every update, and ties them all to one certificate.
      **Notarisation** (€99/yr) is the only clean download route and is hard to justify
      for an internal tool. **MDM** would have been technically best — this Mac is
      Intune-enrolled, and a PPPC profile can pre-approve Accessibility, removing both
      friction points — but it needs IT involvement, which is a conversation worth
      having separately for a tool that types credentials on managed machines.

---

## 5. Manual test matrix (run at the end of phase 1)

| Target | What it proves |
|---|---|
| TextEdit | baseline |
| Terminal.app | fast typing into a PTY; also check Secure Keyboard Entry behaviour |
| Safari address bar | focus restore into a non-text-editor control |
| **Windows App (RDP)** | **the actual use case** — scancode translation, remote-side caret survives reactivation, pacing over latency |
| **Devolutions RDM** | same, second client — the two may behave differently |
| Text with `é`, `ü`, `€`, emoji | layout independence; over RDP also local-vs-remote layout match |
| Multi-line text | Return handling |
| A 2000-character string | pacing, and that cancel still works mid-way |
| Mouse jiggle mid-type | cancellation |
| A password with `!@#$%^&*` | shifted characters in virtual-key mode, if that mode is in use |

---

## 6. Known risks

- **RDP scancode translation** (section 3). The biggest one, and the reason phase 1
  opens with a spike. Worst case, virtual-key mode is required and the dead-key
  handling we hoped to avoid comes back for remote targets.
- **Local versus remote keyboard layout.** If the Mac is on a different layout than
  the remote Windows machine, characters arrive wrong in virtual-key mode. Not
  fixable from our side; the workaround is matching the layouts.
- **Secure Input Mode.** When a password field has focus, or Terminal has Secure
  Keyboard Entry on, macOS may drop synthetic events. Unknown until tested; if it
  bites, it is a documented limitation, not something to engineer around.
- **Fast typing gets dropped** by some apps that do not drain their event queue
  quickly. That is exactly why the speed setting exists — the "slow" preset is the
  escape hatch, not a nicety.
- **TCC grant churn** during development, unless the self-signed cert is in place.
- **SwiftPM without Xcode** is the one unproven part of the toolchain. Phase 0
  exists specifically to prove it before anything is built on top.

## 7. Non-goals

Images or files in history · iCloud/sync · cross-platform · App Store ·
clipboard *editing* · snippets/templates · encryption at rest (masking is visual
only, and the README will say so).
