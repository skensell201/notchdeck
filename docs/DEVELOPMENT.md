# Development

## Requirements

- macOS 26.0 or later
- Swift 6.2+ toolchain (Xcode 26 command line tools)
- `rsvg-convert` only if you change the icon (`brew install librsvg`)

## First-time setup

Create a local code signing identity, so rebuilt bundles keep the same
designated requirement. Without it macOS treats every build as a new app and
asks for permissions again:

```bash
./Scripts/make-dev-cert.sh
```

macOS asks for your login password once while it trusts the certificate.

## Build and run

```bash
swift test          # unit tests
./Scripts/bundle.sh # build, bundle, sign — prints the .app path
./Scripts/run.sh    # build, bundle, sign, launch
```

NotchDeck is an accessory app with no Dock icon and no window to close. The
menu bar item's **Quit NotchDeck** quits it; `pkill -x NotchDeck` does the same,
because `SIGTERM` goes through the same clean shutdown. A wedged app ignores
`SIGTERM` and needs `kill -9`, after which the next launch reaps the orphaned
adapter subprocess.

## Scripts

| Script | Purpose |
|---|---|
| `Scripts/make-dev-cert.sh` | Creates the `NotchDeck Dev` signing identity |
| `Scripts/bundle.sh` | Builds and assembles a signed `build/NotchDeck.app` (`CONFIG=release` for a release build) |
| `Scripts/run.sh` | Bundles and launches, replacing a running instance |
| `Scripts/build-media-adapter.sh` | Builds the vendored MediaRemote adapter framework |
| `Scripts/make-dmg.sh` | Builds a release and writes `build/NotchDeck-<version>.dmg` |
| `Scripts/make-icon.sh` | Renders `Resources/AppIcon.svg` into `Resources/AppIcon.icns` and `Resources/StatusIcon.svg` into `Resources/StatusIcon.pdf` |

## Project layout

| Target | Contents |
|---|---|
| `NotchCore` | State machine, gestures, geometry — pure Swift, fully unit-tested |
| `NotchUI` | SwiftUI shell and the notch shape |
| `NotchWindow` | `NSPanel` surfaces, screen adapters, event monitors |
| `Media` | Now playing: adapter subprocess, decoder, transport commands, player and peek views |
| `Shelf` | File shelf: store, tiles, drag-out, AirDrop |
| `Clipboard` | Clipboard history: store, pasteboard watcher, search |
| `Pomodoro` | Pomodoro timer: phase machine, countdown, peek |
| `Stats` | Battery, CPU, memory and network throughput |
| `Mirror` | Camera preview with a mirrored image |
| `Shortcuts` | Shortcuts launcher: list, pin, run |
| `Agenda` | Calendar: upcoming events and meeting links |
| `LiveActivities` | Power and audio-device announcements |
| `SystemHUD` | Suppressing the system volume overlay |
| `Preferences` | Stored settings, clamped, and the login item |
| `SettingsUI` | The settings window: general, modules, notch, permissions |
| `NotchDeckApp` | Entry point, menu bar item, wiring |
| `Support` | Shared logging |

Other directories:

- `Resources/` — `Info.plist`, the icon source (`AppIcon.svg`) and the rendered `AppIcon.icns`
- `ThirdParty/mediaremote-adapter/` — vendored now-playing adapter (BSD 3-Clause)
- `docs/specs/` — design specs

## Testing

`swift test` covers everything except `NotchUI` and `NotchWindow`, which have no
automated tests by design. Before merging a change that touches rendering or
windowing, go through the [manual checklist](TESTING.md).

## The icon

`Resources/AppIcon.svg` is the source of truth. It is full-bleed on purpose:
macOS 26 masks an app icon into its own squircle, so an icon with a plate of its
own would end up as a tile inside a tile. After editing it:

```bash
./Scripts/make-icon.sh
```

and commit the regenerated `AppIcon.icns` alongside. The README image,
`docs/assets/icon-256.png`, is the same artwork clipped to rounded corners.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Add a section to [`CHANGELOG.md`](../CHANGELOG.md).
3. Commit as `chore: cut X.Y.Z` and tag `vX.Y.Z`.
4. Build the disk image:

   ```bash
   ./Scripts/make-dmg.sh
   ```

5. Push the commit and the tag, and publish a GitHub release with the image:

   ```bash
   gh release create vX.Y.Z build/NotchDeck-X.Y.Z.dmg --title "NotchDeck X.Y.Z" --notes-file notes.md
   ```

The image is not notarized, so release notes should repeat the
[first-launch instructions](../README.md#first-launch).

Launch at login needs the app in `/Applications`; from a build directory the
switch reports the failure rather than silently doing nothing.
