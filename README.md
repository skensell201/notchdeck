# NotchDeck

A macOS utility surface built into the MacBook notch — and onto a synthetic notch
on displays that do not have one.

Design: [`docs/superpowers/specs/2026-09-02-notchdeck-design.md`](docs/superpowers/specs/2026-09-02-notchdeck-design.md)

## Requirements

- macOS 26.0 or later
- Swift 6.3 toolchain (Xcode 26 command line tools)

## First-time setup

Create a local code signing identity so rebuilt bundles keep the same designated
requirement. Without it macOS treats every build as a new app and re-prompts for
permissions:

```bash
./Scripts/make-dev-cert.sh
```

macOS asks for your login password once while trusting the certificate.

## Build and run

```bash
swift test          # unit tests
./Scripts/bundle.sh # build, bundle, sign — prints the .app path
./Scripts/run.sh    # build, bundle, sign, launch
```

NotchDeck is an accessory app with no Dock icon and no window to close from; the
menu bar item's "Quit NotchDeck" is the only way to quit it.

## Manual verification

`NotchUI` and `NotchWindow` have no automated tests by design — this checklist is
their entire verification story. Run through it by hand, on a MacBook with at
least one external display attached, before merging any change that touches
rendering or windowing:

- [ ] The menu bar item appears and its menu opens.
- [ ] A black notch surface sits at the top centre of the built-in display, matching the physical notch.
- [ ] A synthetic notch of the same shape appears at the top centre of the external display.
- [ ] Moving the pointer onto the notch expands it after a short dwell; moving away collapses it.
- [ ] Scrolling down over the notch expands it immediately; scrolling up collapses it.
- [ ] Clicking the expanded notch pins it; clicking elsewhere on screen collapses it.
- [ ] Clicking anywhere outside the visible black shape — including the strip of screen the panel covers but does not draw on — activates the app underneath.
- [ ] The notch stays visible after switching Spaces and above a full-screen window.
- [ ] Unplugging and replugging the external display leaves exactly one notch per screen.
- [ ] Changing a connected display's resolution (or scale/arrangement) moves and resizes its notch to match the new geometry, rather than leaving it at the old coordinates.
- [ ] "Quit NotchDeck" terminates the process and removes every surface.
- [ ] The menu bar under the panel still works — menu titles open, status icons and Control Center respond. (The panel sits above the menu bar and reserves 620×200 across the top centre of every screen, so a click-through regression shows up here first.)
- [ ] Scrolling over an ordinary window still scrolls that window.
- [ ] Attaching a display while the notch is open gives the new display an open notch too, not a collapsed one.
- [ ] Running `Contents/MacOS/NotchDeck` directly while an instance is already running is not a supported path; use `./Scripts/run.sh`.

## Layout

| Target | Contents |
|---|---|
| `NotchCore` | State machine, gestures, geometry — pure Swift, fully unit-tested |
| `NotchUI` | SwiftUI shell and the notch shape |
| `NotchWindow` | `NSPanel` surfaces, screen adapters, event monitors |
| `NotchDeckApp` | Entry point, menu bar item, wiring |
| `Support` | Shared logging |
