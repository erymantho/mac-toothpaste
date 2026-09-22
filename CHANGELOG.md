# Changelog

Versions here are git tags, not downloads — Toothpaste is cloned and built, for the
reasons in [the README](README.md#why-build-rather-than-download). To move to one:

```sh
git pull && make install
```

Settings → General shows the running version *and the commit it was built from*. Quote
that in a bug report: with clone-and-build everyone sits on whatever commit they last
pulled, so a version number alone does not identify a build.

## Unreleased

**Fixed: the panel could not be moved on macOS 27.** Dragging it by its header stopped
working, and no setting or restart brought it back. The cause is outside this app:
macOS 27 no longer lets a SwiftUI-hosted window be dragged by its background, which is
how the panel had always been moved. The header now starts the drag itself.

Nothing else changes. The header is still the only place the panel can be dragged from,
so brushing past a row cannot shift it, and the profile menu and settings button in the
header still work as before.

## 1.2.0 — 2026-09-18

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

The settings window is a little taller, so the new section fits without scrolling.

**This release needs one manual update, and it is the last one.** Your current copy was
built before it recorded where its source is, so it cannot update itself yet:

```sh
git pull && make install
```

After that the app takes over, and every tagged release from here shows up in Settings →
General by itself.

## 1.1.1 — 2026-09-17

**Fixed: the panel was unreadable on a light system theme.** It painted its own
background with fixed near-black greys, while its text used the system's semantic
colours, which follow the theme regardless. In Dark Mode the two happen to agree and it
looks designed. In Light Mode the text turned near-black as well and the panel arrived
as a black box. Every surface colour now states a value for both themes.

Warning and confirmation text was wrong in the same way, and measurably: the system's
orange and green reach about 2:1 contrast against a light background, which is below
readable for text reporting a missing permission or characters that cannot be typed.
They now sit near 4.5:1 in light and are unchanged in dark. This also covered the
settings window and the onboarding screen.

Found by a tester rather than here. Everyone who had run the app was running Dark Mode,
and nothing about the code says which theme it was written against.

**Added: Settings → General → Appearance — Automatic, Light, Dark.** Automatic is the
default and follows the system, so an existing install behaves exactly as before without
being touched. The other two are worth having because the panel is a dark HUD by design:
a light desktop does not necessarily mean you want a light panel, and a dark one does
not mean you want a dark panel over a bright remote session. The choice applies to every
window at once and takes effect while you watch.

**Added: `make appearances`.** Renders the panel, the settings window and the onboarding
screen offscreen under all three choices and writes PNGs to `dist/appearances`. No
window is ever put on screen and no focus is taken. It exists because the bug above was
invisible without switching the whole machine over, which is why it was never checked.

No behaviour, defaults or stored data changed.

## 1.1.0 — 2026-09-15

**Removed the hover detail strip.** It showed the full text of a row that was too long
to fit. It worked, and it was careful — it appeared only when the text would have been
truncated anyway, and never for a masked entry, so it could not print a secret. It went
because reading a long command before sending it turned out to be wanted rarely, while
the strip was on screen most of the time, and a panel you glance at pays for anything
permanently present. Nothing replaced it, and the underlying problem stands: rows are
one line, so a 300-character command is not fully visible anywhere.

This was the first release after other people started using the tool, which raises the
bar for removals — they now cost someone their habits.

**Fixed the build against Command Line Tools 6.4**, which broke it without any change
here. CLT 6.4 ships a macOS 27 SDK whose SwiftUI declares `@State` and friends as
macros, without shipping the plugin that implements them, so every SwiftUI file fails to
compile. Full Xcode has the plugin; Command Line Tools does not.
`scripts/select-sdk.sh` picks the newest SDK that predates the requirement, and returns
nothing once the plugin appears, so the workaround removes itself.

Worth knowing if it recurs: clone-and-build means a toolchain update can break every
colleague at once, with no bad commit to point at.

## 1.0.0 — 2026-09-09

First release, and the point at which distribution was settled as clone-and-build.

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
