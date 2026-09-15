# NotchDeck

A macOS utility surface built into the MacBook notch — and onto a synthetic notch
on displays that do not have one.

Design: [`docs/superpowers/specs/2026-09-02-notchdeck-design.md`](docs/superpowers/specs/2026-09-02-notchdeck-design.md),
[`docs/superpowers/specs/2026-09-02-p1-media-and-shelf-design.md`](docs/superpowers/specs/2026-09-02-p1-media-and-shelf-design.md)

## Installing

Download `NotchDeck-<version>.dmg` from the
[latest release](https://github.com/skensell201/notchdeck/releases/latest), open it,
and drag NotchDeck to Applications.

**The first launch needs a trip through System Settings.** The app is signed but
not notarized — notarization needs a paid Developer ID, and the vendored
MediaRemote adapter's whole technique is an end-run around a private framework,
so the App Store was never a destination either. macOS 26 shows *"Apple could not
verify NotchDeck is free of malware"* and offers only a Done button.

Double-click NotchDeck once and dismiss that dialog, then open **System Settings
→ Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to
the message about NotchDeck. Confirm, and it launches — once. Every launch after
that is an ordinary one.

Control-clicking and choosing Open is the advice you will find everywhere else,
and it no longer works: macOS 15 removed that bypass. If you would rather not
visit System Settings, clearing the quarantine flag does the same job:

```bash
xattr -d com.apple.quarantine /Applications/NotchDeck.app
```

NotchDeck has no Dock icon. It lives in the menu bar, and that is where Settings
and Quit are.

Two tabs ask for permission the first time you open them — Mirror for the camera,
Calendar for events. Everything else needs nothing. Declining leaves that one tab
explaining itself; the rest of the app is unaffected.

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

NotchDeck is an accessory app with no Dock icon and no window to close from. The
menu bar item's "Quit NotchDeck" quits it; `pkill -x NotchDeck` is equivalent,
since `SIGTERM` is routed through the same clean shutdown. A wedged app ignores
`SIGTERM` and needs `kill -9`, after which the next launch reaps the orphaned
adapter subprocess.

## Releasing

```bash
./Scripts/make-dmg.sh
```

Builds the release configuration and writes `build/NotchDeck-<version>.dmg` with an
`/Applications` symlink. The image is **not notarized** — that needs a paid
Developer ID, and the vendored MediaRemote adapter's whole technique is an
end-run around a private framework, so the App Store was never a destination
either. Whoever installs it therefore has to clear Gatekeeper by hand the first
time, as the Installing section above describes.

Launching at login needs the app to live in `/Applications`; from a build
directory the switch reports the failure rather than silently doing nothing.

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
- [ ] On a dark wallpaper the collapsed notch is visible enough to aim at.
- [ ] On a light wallpaper the expanded panel has a clear edge and does not look pasted on.
- [ ] No glow or bright line appears above the panel, across the menu bar or the bezel.
- [ ] Clicks still pass through the reserved margin around the panel — the bloom must not swallow them.
- [ ] With music playing in any app — Music, Spotify, a browser tab — the collapsed notch shows its artwork and an animated indicator.
- [ ] Opening the notch shows the track's artwork, title and artist, a scrubber that advances once a second, and working previous / play-pause / next.
- [ ] Dragging the scrubber seeks the track on release.
- [ ] Pausing in the source app is reflected within a second, and the visualiser rests.
- [ ] A two-finger horizontal swipe over the notch changes track.
- [ ] Stopping playback entirely makes the peek disappear after the staleness window, without the panel losing the track.
- [ ] With nothing ever played since login, the panel says "Nothing playing" rather than showing a stale track.
- [ ] Quitting cleanly — menu or `pkill -x NotchDeck` — with nothing playing leaves no orphaned `perl` process: `pgrep -f mediaremote-adapter` is empty within a couple of seconds.
- [ ] After `kill -9` of a running instance, the orphaned `perl` survives; the next launch reaps it, and `pgrep -fl mediaremote-adapter` then shows exactly one `perl`, the new instance's.
- [ ] Hovering the widened peek band (not just the bare notch) opens the panel.
- [ ] With a track playing, `kill -9` the `perl` adapter process (not the app); the peek recovers within a few seconds.
- [ ] Launching with a track that has been paused for more than 90 s shows no peek; the expanded panel still shows the track.
- [ ] A two-finger swipe **left** over the notch skips to the next track; right goes to the previous one.
- [ ] Media-key fallback: rename `Contents/Frameworks/MediaRemoteAdapter.framework` inside a built bundle so the probe fails, relaunch, and confirm the transport buttons still control playback. If they do not, note that synthesising media keys needs Accessibility permission on this macOS.
- [ ] Dragging a file from Finder onto the collapsed notch opens it and switches to the Shelf tab mid-drag.
- [ ] Dragging away without dropping closes the notch after the grace period.
- [ ] Dropping one or several files adds a tile per file, newest drop first, original order within a drop.
- [ ] A tile drags back out to the Desktop and Finder copies the real file.
- [ ] Right-clicking a tile offers Reveal in Finder, Quick Look, Copy and Remove, and each works.
- [ ] Quitting and relaunching keeps the shelf; a file deleted meanwhile shows dimmed rather than vanishing.
- [ ] Dropping onto the AirDrop zone highlights it during the drag and opens the AirDrop picker on release.
- [ ] Clicking the AirDrop zone with items on the shelf offers all of them.
- [ ] Clear asks for confirmation and empties the shelf without touching the files.
- [ ] Copying text in any app adds it to the Clipboard tab within about half a second; clicking an entry copies it back.
- [ ] Copying from a password manager adds nothing to the history.
- [ ] A pinned clipboard entry survives Clear and survives the history filling up.
- [ ] Starting the timer and closing the notch leaves the countdown visible in the collapsed band.
- [ ] A finished pomodoro phase chimes and moves to the next phase on its own.
- [ ] The Stats tab shows battery, CPU, memory and network, and the numbers move.
- [ ] Network throughput may read as unknown for a couple of seconds every few hours — that is the 32-bit counter wrapping, not a bug.
- [ ] Opening the Mirror tab asks for camera access once, then shows a mirrored preview; the camera light goes out when the notch closes.
- [ ] Denying camera access leaves a button that opens the right System Settings pane.
- [ ] Opening the Calendar tab asks for calendar access once, then lists today and the next few days.
- [ ] A meeting with a Zoom, Meet, Teams or Webex link shows a join button that opens it.
- [ ] Birthdays do not appear in the calendar list; meetings that ended more than fifteen minutes ago do not either.
- [ ] The Shortcuts tab lists your shortcuts and running one works; with no shortcuts saved the list is empty, which is correct.
- [ ] All eight tabs fit either side of the camera housing and none is hidden behind it.
- [ ] Plugging and unplugging the charger announces itself.
- [ ] Connecting AirPods or another audio device sags the notch and drops a capsule with the device's name under it; disconnecting does the same and says so.
- [ ] Putting Bluetooth headphones back on announces them even though they never left the device list.
- [ ] One drop per action: connecting announces once, not once for the device and once for the sound moving to it.
- [ ] A drop arriving while the panel is open falls out of the panel and leaves it open.
- [ ] Hovering the notch while a drop is falling does not cut it short.
- [ ] The gap between the notch and a hanging drop is not clickable — a window under it still takes the click.
- [ ] Turning on "Replace the system volume overlay" in the menu bar stops the macOS overlay; turning it off brings it back.
- [ ] Quitting with the overlay replaced restores it — check the volume keys still show the system overlay afterwards.
- [ ] "Settings…" in the menu bar opens a window, and opening it again brings the same window forward.
- [ ] Dragging a module in the Modules tab reorders the tab strip in the notch straight away.
- [ ] Unchecking a module removes its tab; unchecking all of them leaves an explanation, not an empty frame.
- [ ] Changing the hover dwell changes how long the notch waits, without relaunching.
- [ ] Changing the synthetic notch size resizes the notch on an external display, without relaunching.
- [ ] The volume-overlay switch in Settings and the menu bar item agree with each other.
- [ ] The Permissions tab shows camera and calendar status and each button opens the right pane.
- [ ] Launch at login turns on when the app is in /Applications, and explains itself when it is not.
- [ ] Quitting and relaunching keeps the module order and everything else set in the window.
- [ ] With "Dismiss with Esc" on and Accessibility granted, Esc closes a pinned notch.
- [ ] `./Scripts/make-dmg.sh` produces a disk image that mounts and installs by dragging.

## Layout

| Target | Contents |
|---|---|
| `NotchCore` | State machine, gestures, geometry — pure Swift, fully unit-tested |
| `NotchUI` | SwiftUI shell and the notch shape |
| `NotchWindow` | `NSPanel` surfaces, screen adapters, event monitors |
| `Media` | The now-playing module: adapter subprocess, decoder, transport commands, expanded player and peek views |
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

## Acknowledgements

Now-playing state comes from [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
v0.7.6 (commit `3ac3d4b`), vendored as source under
[`ThirdParty/mediaremote-adapter/`](ThirdParty/mediaremote-adapter/) and built by
`Scripts/build-media-adapter.sh` into the `MediaRemoteAdapter.framework` and
`MediaRemoteAdapterTestClient` that ship inside the app bundle. It is licensed
under the BSD 3-Clause License; the full text is in
[`ThirdParty/mediaremote-adapter/LICENSE`](ThirdParty/mediaremote-adapter/LICENSE)
and is reproduced here as that license requires:

> BSD 3-Clause License
>
> Copyright (c) 2025, Jonas van den Berg and contributors
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this
>    list of conditions and the following disclaimer.
>
> 2. Redistributions in binary form must reproduce the above copyright notice,
>    this list of conditions and the following disclaimer in the documentation
>    and/or other materials provided with the distribution.
>
> 3. Neither the name of the copyright holder nor the names of its
>    contributors may be used to endorse or promote products derived from
>    this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
> AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
> IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
> FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
> DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
> CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
> OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
