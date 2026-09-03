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
- [ ] Quitting and relaunching leaves no orphaned `perl` process: `pgrep -f mediaremote-adapter` is empty.

## Layout

| Target | Contents |
|---|---|
| `NotchCore` | State machine, gestures, geometry — pure Swift, fully unit-tested |
| `NotchUI` | SwiftUI shell and the notch shape |
| `NotchWindow` | `NSPanel` surfaces, screen adapters, event monitors |
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
