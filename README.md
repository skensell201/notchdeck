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
./Scripts/run.sh    # build, bundle, sign, launch
```

Quit from the menu bar item.

## Layout

| Target | Contents |
|---|---|
| `NotchCore` | State machine, gestures, geometry — pure Swift, fully unit-tested |
| `NotchUI` | SwiftUI shell and the notch shape |
| `NotchWindow` | `NSPanel` surfaces, screen adapters, event monitors |
| `NotchDeckApp` | Entry point, menu bar item, wiring |
| `Support` | Shared logging |
