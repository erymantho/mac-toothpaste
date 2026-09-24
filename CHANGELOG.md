# Changelog

Versions here are git tags, not downloads — Toothpaste is cloned and built, for the
reasons in [the README](README.md#why-build-rather-than-download). To move to one:

```sh
git pull && make install
```

Settings → Updates shows the running version *and the commit it was built from*. Quote
that in a bug report: with clone-and-build everyone sits on whatever commit they last
pulled, so a version number alone does not identify a build.

Each version lists what is new apart from what was fixed, which is the same split the app
shows before and after an update. *Changed* is for what behaves differently without being
new, and *Removed* for what is gone.

## Unreleased

### New

**Your accent colour shows what the panel is doing.** It was already the colour of the pin
stripe and of an entry waiting for its destination; it now also does three things that
had no colour before.

- **The row being typed fills from left to right** as the characters go out, flashes when
  the last one has gone, and fades. Cancel with Esc and it stays where it stopped for a
  moment, so you can see how far it got. Over a remote session a long entry takes a few
  seconds, and until now the only sign of progress was the status line.
- **The row under the pointer is lit faintly**, which shows where a click would land. It
  works while another window is in front, which is how the panel is normally used.
- **A dragged entry carries an outline and a glow** in the same colour.

All three sit behind or around the text, never in it. The accent is whatever colour you
picked for macOS, and some of them — yellow above all — are unreadable as text on a light
background.

### Changed

**Dragging an entry to a field now works without switching it on first.** Drag an entry
out of the panel, let go over a field, and Toothpaste clicks there and types it. It is on
by default; Settings → General still switches it off.

If you never touched that switch, updating turns the feature on. If you switched it off
yourself, it stays off. Worth knowing on a managed machine: with it on, Toothpaste posts a
mouse click as well as keystrokes, and letting go over something that is not a text field
clicks that instead.

**The pointer stays the normal arrow while you drag an entry.** It used to turn into a
crosshair. The tip of the arrow is where Toothpaste clicks, as with any click, and the
entry travelling beside it already shows that a drag is under way.

**No window opens after an update that worked.** You read the release notes just before
updating, and the arrow leaving the menu bar icon says it worked; a window repeating it
was one more thing to close. Settings → Updates still shows what is new since your old
version. An update that fails still opens a window saying why, because the old version
coming back looks exactly like the new one arriving.

## 1.3.1 — 2026-09-23

### Fixed

**Characters that need Shift arrived without it in Windows App.** `#` came out as `3`, `^`
as `6`, `A` as `a` — anything shifted, passwords included. Windows App 11.4 checks on every
key *which* Shift key the event says is down, left or right, and releases Shift on the
remote side when it says none. A real keyboard always says; Toothpaste only said that a
Shift was down. It now says which, the way a keyboard does. Typing into Mac apps is
unchanged.

Leave Windows App's *Keyboard Mode* on **Scancode**, its default. Its Unicode mode typed
nothing at all in testing on 11.4.1, from the Mac's own keyboard as well, so nothing on
this side can help in that mode.

## 1.3.0 — 2026-09-23

**Coming from 1.2.0 or 1.2.1, this one update still goes through that version's own
updater.** So the notes it shows beforehand are plain text, and no window opens afterwards
to say it worked. Settings → Updates in the new version shows what you got. From the next
update on, both work.

### New

**Drag an entry to a field to click and type there — off by default.** Press an entry,
drag to where you want it, let go: Toothpaste clicks that spot and types. It works in
remote sessions, because the click is synthesised the same way the keystrokes are.

While you drag, the entry itself travels beside the pointer — the row as it looks in the
panel, tilted slightly as if picked up — so you can see what is about to be typed. A masked
entry travels as dots.

It is off until you switch it on in Settings → General, and that default is deliberate.
With it off the app posts keystrokes and nothing else; with it on it also clicks, which
is a different thing to have to explain about a tool on a managed machine. It also adds a
failure the existing flow does not have: let go over something that is not a text field
and that is what gets clicked. Releasing back over the panel cancels, and the pointer
becomes a crosshair while you are dragging so you can see what is about to happen.

**An update tells you it worked.** Toothpaste used to finish an update by quietly
reappearing, which looks exactly like a restart — so the one thing you wanted to know
after pressing the button was the one thing it did not say. It now opens a window naming
the version you came from and showing the release notes for the one you got.

A failed update gets the same window, which is the more important half: it used to leave
a note in the settings window and nothing else, so an update could fail in silence.

**Release notes say what is new apart from what was fixed**, before an update in Settings
→ Updates and after it in the window above. They also cover every version since yours
rather than only the newest, so a feature is not lost because a fixes-only release came
out after it. Older versions, written before there was a split, still read as one block
of text. When no newer version is on offer, Settings → Updates shows the notes for the
version you are running, so the report after an update can be read again after it has
been closed.

**You can switch off masking of entries marked secret.** Password managers tag what they
copy as concealed, and those entries show as dots. Settings → General has a switch for
it, on by default. It changes what is shown and nothing else — concealed entries are
never written to disk either way.

**An available update shows in the menu bar.** The icon gains a small arrow and the
tooltip names the version. Previously it was only visible in settings and in the menu bar
item's right-click menu, both of which need you to go and look, so a release could sit
unnoticed.

### Changed

**Updates have a tab of their own in settings**, and the version moved there with them —
"which version am I on" and "is there a newer one" are the same question. The *Update
to …* item in the menu bar opens that tab directly.

**Deleting a pinned entry asks twice.** The delete button on a pinned row turns into a
confirmation on the first click and clears itself after a few seconds, the way the
*clear* button already did. Unpinned entries still go on one click: they were going to
vanish at the next restart anyway, while a pinned entry is the one thing in the history
that is meant to survive. This exists because everything in the panel now acts on the
click that brings it forward, which is what makes it usable while another window has
focus — and which also means a mis-aimed click can reach a delete button.

### Fixed

**Clicking the panel while another window was in front took two clicks.** The first only
brought the panel forward and was otherwise thrown away. That is the normal way this tool
is used — you pick an entry, click into the window you want it typed into, and come
back — so the wasted click landed on almost every round trip. One click now does what it
was aimed at.

**Text arrived in the field you had selected before, not the one you clicked.** The click
that picks the destination is also the click that puts the caret in the field, and typing
was starting before it had landed — on mouse-down, and over a remote session while the
click was still on its way to the far side. It now waits for the click to finish. If it
still happens on a slow link, raise *Initial delay* for that profile in Settings → Typing
profiles; the caption there says so.

This is what made a username and a password cost two extra clicks: the field had to be
selected in advance, every time.

**Instructions in the panel could be unreadable under some accent colours.** The
"now click the field you want this typed into" banner and the *clear* confirmation were
written in the system accent colour, which is whatever you picked — a yellow accent put
them at about 1.6:1 against a light background. The words are now in the normal text
colour, with the accent kept for the icon and the outline.

## 1.2.1 — 2026-09-22

### Fixed

**The panel could not be moved on macOS 27.** Dragging it by its header stopped working,
and no setting or restart brought it back. The cause is outside this app: macOS 27 no
longer lets a SwiftUI-hosted window be dragged by its background, which is how the panel
had always been moved. The header now starts the drag itself.

Nothing else changes. The header is still the only place the panel can be dragged from,
so brushing past a row cannot shift it, and the profile menu and settings button in the
header still work as before.

## 1.2.0 — 2026-09-18

**This release needs one manual update, and it is the last one.** Your current copy was
built before it recorded where its source is, so it cannot update itself yet:

```sh
git pull && make install
```

After that the app takes over, and every tagged release from here shows up in settings by
itself.

### New

**Toothpaste can update itself.** Settings → General checks your clone's remote for a
newer version tag at launch, shows the release notes for it, and offers a button that
quits the app, pulls, rebuilds and starts the new version. About a minute, no terminal.
The menu bar item shows it too, so it is visible without opening settings.

The confirmation says two things plainly. Unpinned history is never written to disk, so
it is gone after the restart — pin anything you still need first. And the button builds
and runs whatever is in the repository, which is what `git pull && make install` has
always done; the button only removes the terminal from in front of it. Doing it by hand
still works exactly as before.

If the build fails, the old version comes back by itself and the app reports what went
wrong on next launch, with the full build log one click away.

**Checking is the only thing Toothpaste does over the network**, and it can be switched
off. It asks your own clone's remote for its version tags — nothing about you or your
clipboard is sent. Before this the app made no network calls at all, which was worth
giving up on purpose rather than quietly.

### Changed

The settings window is a little taller, so the new section fits without scrolling.

## 1.1.1 — 2026-09-17

### New

**Settings → General → Appearance — Automatic, Light, Dark.** Automatic is the default
and follows the system, so an existing install behaves exactly as before without being
touched. The other two are worth having because the panel is a dark HUD by design: a
light desktop does not necessarily mean you want a light panel, and a dark one does not
mean you want a dark panel over a bright remote session. The choice applies to every
window at once and takes effect while you watch.

**`make appearances`.** Renders the panel, the settings window and the onboarding screen
offscreen under all three choices and writes PNGs to `dist/appearances`. No window is
ever put on screen and no focus is taken. It exists because the bug below was invisible
without switching the whole machine over, which is why it was never checked.

### Fixed

**The panel was unreadable on a light system theme.** It painted its own background with
fixed near-black greys, while its text used the system's semantic colours, which follow
the theme regardless. In Dark Mode the two happen to agree and it looks designed. In
Light Mode the text turned near-black as well and the panel arrived as a black box.
Every surface colour now states a value for both themes.

Warning and confirmation text was wrong in the same way, and measurably: the system's
orange and green reach about 2:1 contrast against a light background, which is below
readable for text reporting a missing permission or characters that cannot be typed.
They now sit near 4.5:1 in light and are unchanged in dark. This also covered the
settings window and the onboarding screen.

Found by a tester rather than here. Everyone who had run the app was running Dark Mode,
and nothing about the code says which theme it was written against.

## 1.1.0 — 2026-09-15

This was the first release after other people started using the tool, which raises the
bar for removals — they now cost someone their habits.

### Removed

**The hover detail strip.** It showed the full text of a row that was too long to fit.
It worked, and it was careful — it appeared only when the text would have been truncated
anyway, and never for a masked entry, so it could not print a secret. It went because
reading a long command before sending it turned out to be wanted rarely, while the strip
was on screen most of the time, and a panel you glance at pays for anything permanently
present. Nothing replaced it, and the underlying problem stands: rows are one line, so a
300-character command is not fully visible anywhere.

### Fixed

**The build against Command Line Tools 6.4**, which broke without any change here. CLT
6.4 ships a macOS 27 SDK whose SwiftUI declares `@State` and friends as macros, without
shipping the plugin that implements them, so every SwiftUI file fails to compile. Full
Xcode has the plugin; Command Line Tools does not. `scripts/select-sdk.sh` picks the
newest SDK that predates the requirement, and returns nothing once the plugin appears, so
the workaround removes itself.

Worth knowing if it recurs: clone-and-build means a toolchain update can break every
colleague at once, with no bad commit to point at.

## 1.0.0 — 2026-09-09

First release, and the point at which distribution was settled as clone-and-build.

### New

- Clipboard history in the menu bar, opened with ⌃⌥V or the menu bar icon.
- **Types the entry as keystrokes instead of pasting it**, which is the whole point:
  it works into RDP sessions, VM consoles, browser terminals and password fields, where
  ⌘V is blocked or ignored. Real virtual keycodes, not Unicode injection — remote
  clients read the key code, and a Unicode payload arrives as the letter `a`.
- Choosing an entry *arms* it; the next click in any window is the destination, so you
  pick the exact field, including inside a remote session. The panel names that
  destination live while you click around.
- Typing profiles per destination: pacing, modifier handling and whether the Unicode
  fallback is allowed. Remote targets need different answers from local ones.
- Pinning, search, masking of entries a password manager marked secret, and a history
  cap with optional expiry.
- Only pinned entries are written to disk, as plaintext JSON, and entries marked
  concealed by the source app are never written at all.
- Settings: hotkey, history size, retention, launch at login, and a layout check that
  reports which characters cannot be typed on the current keyboard layout.
