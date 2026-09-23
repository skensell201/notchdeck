# NotchDeck P3 — Live Activities

**Date:** 2026-09-03
**Status:** Draft
**Parent spec:** [`2026-09-02-notchdeck-design.md`](2026-09-02-notchdeck-design.md)
**Depends on:** P0–P2, all merged.

The notch reacts to what the Mac is doing: plug in the charger and it says so, change the volume and it shows the level, connect AirPods and it names them.

---

## 1. What already exists

P0's state machine has carried `.peek(PeekPayload)` since the first commit: a timed mode entered by a `.liveActivity` event, which times out back to `.closed` and is deliberately ignored while the panel is open. It is tested and it has never fired, because nothing has ever sent one. P3 is the senders.

Note the distinction P1a introduced and P3 must respect: a *live activity* is a timed announcement and uses `.peek`; *live content* — a playing track, a running timer — is not timed and widens the collapsed notch through `hasLiveContent` instead. Charging is an announcement. A pomodoro is not.

## 2. Presentation

`PeekPayload` currently carries an identifier and a duration, and the shell renders the identifier as text — placeholder from P0. It gains the fields an announcement needs, all plain values so `NotchCore` stays free of SwiftUI: a symbol name, a title, an optional detail, and an optional level between zero and one for the things that have one.

The shell renders them in the peek band: symbol on one side of the camera housing, title and detail on the other, and a level bar underneath when a level is present.

Replacement is already correct in the reducer — a second activity replaces the first and restarts its timeout — which is exactly right for volume, where a dozen arrive as the user holds the key down.

## 3. Sources

Each source is a small object that observes one thing and emits `LiveActivity` values. All sit behind a protocol so the wiring is testable without hardware.

| Source | Mechanism | Emits |
|---|---|---|
| Power | IOKit power-source notifications | charger connected and disconnected, and a warning when the battery falls below a threshold |
| Volume | CoreAudio property listener on the default output device's virtual main volume | the new level, with a muted state |
| Audio output | CoreAudio default-output-device changes | the new device's name — this is what makes AirPods announce themselves |

**Deliberately not built, with reasons.** *Brightness* has no public read API; the private `DisplayServices` and `CoreDisplay` entry points are exactly the kind of thing that breaks on a macOS update, and the alternative — watching the brightness keys — needs Accessibility for a cosmetic feature. *Focus mode* is only readable by parsing a file in `~/Library/DoNotDisturb`, which is undocumented and has changed shape between releases. Both are better absent than flaky; they can come back if Apple ever exposes them.

Two announcements already have their triggers built and only need to be routed here: a pomodoro phase finishing, and files landing on the shelf.

## 4. Replacing the system HUD

macOS draws its own volume overlay in the middle of the screen. Showing ours as well is worse than showing neither, so the volume activity is only useful with the system one suppressed.

The mechanism is `OSDUIHelper`: suspending it stops the overlay. It respawns, so suppression has to be maintained rather than performed once.

This is fragile by nature — an undocumented agent, suppressed by force — so:

- it is **off by default** and switched on deliberately;
- it is restored on quit, including on a crash, by never leaving the agent suspended longer than one supervision interval;
- if suppression stops working after a macOS update, the visible symptom is two overlays rather than a broken app.

## 5. Testing

Unit tested, pure: the payload built for each activity kind, the volume level to bar mapping including mute, the battery threshold crossing (it must announce once on the way down, not repeatedly), the device-name change filter (no announcement when the name is unchanged), and the suppression supervisor's decision logic.

Behind protocols with fakes: IOKit, CoreAudio, and the process control used for suppression.

Not unit tested: that the real overlay actually disappears, which is a human check on a machine.

## 6. Out of scope

- Brightness and Focus announcements, per section 3
- Replacing the brightness HUD, which has the same problem
- Notification mirroring: reading other apps' notifications needs entitlements NotchDeck cannot get
