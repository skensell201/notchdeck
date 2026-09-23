# NotchDeck P4 — Settings and Release

**Date:** 2026-09-03
**Status:** Draft
**Parent spec:** [`2026-09-02-notchdeck-design.md`](2026-09-02-notchdeck-design.md)
**Depends on:** P0–P3, all merged.

Everything built so far is configured by editing constants. P4 makes it the user's.

---

## 1. What has to become settable

The pieces that already exist as tunables and were always meant to reach a settings window:

| Setting | Where it lives today |
|---|---|
| Which modules appear, and in what order | `ModuleLayout`, built empty on every launch |
| Synthetic notch size on displays without one | `NotchSurfaceManager(syntheticSize:)` |
| Hover dwell and exit grace | `NotchTiming` |
| Replace the system volume overlay | `SystemHUDController`, currently a menu bar toggle |
| Clipboard capacity and per-app exclusions | `ClipboardStore` constructor arguments |
| Launch at login | Does not exist |

`ModuleLayout` was built in P1a to be persisted — it deliberately keeps disabled modules in place and preserves identifiers a build does not recognise — and has been thrown away on every launch since. P4 is what it was for.

## 2. Preferences

One `Preferences` object over `UserDefaults`, observable so the settings window and the running app see the same values. Each setting has a default that matches today's hard-coded constant, so an existing install behaves identically until something is changed.

Reading is direct. Writing applies immediately — there is no Apply button, because every one of these settings is cheap to change and instantly visible, and a preview the user cannot trust is worse than no preview.

The layout is the one piece with a migration concern: a stored layout naming a module this build lacks must survive a round trip, so downgrading does not silently discard a newer module's position. `ModuleLayout` already does this and has a test for it.

## 3. The settings window

An ordinary `NSWindow` — not the notch. Four tabs:

- **General** — launch at login, replace the system volume overlay, hover dwell and exit grace.
- **Modules** — every registered module with a checkbox and a drag handle, in layout order. Disabling the last enabled module is allowed; the panel then says so rather than showing an empty frame.
- **Notch** — synthetic notch size for displays without one, previewed live on those displays.
Clipboard capacity and exclusions are read from preferences at launch but have no control in the window yet: they are the two settings a person changes once, if ever, and every tab that fits already has a better use for the room. `defaults write` reaches them until a tab earns the space.

- **Permissions** — the status of camera and calendar access, and a button to the right System Settings pane. Read-only: an app cannot revoke its own grants, and pretending otherwise would be a lie.

The window is the only part of NotchDeck that activates the app, so it is also the only place ordinary keyboard input works.

## 4. Launch at login

`SMAppService.mainApp`. The registration can fail — most often because the app is running from a build directory rather than `/Applications` — and when it does the window says so plainly rather than leaving a switch that silently does nothing.

## 5. Dismissing with Esc

P0 built `.escapePressed` into the state machine and never wired it, because a global key monitor needs Accessibility and the rest of the app needs no permission at all. P4 wires it, guarded: the monitor is installed only when Accessibility is already granted, and the setting explains what it costs. Everything else keeps working without it.

## 6. Release

`Scripts/make-dmg.sh` builds the release configuration, assembles the bundle, signs it with whatever identity exists, and produces a compressed disk image with an `/Applications` symlink.

Not notarized: notarization needs a paid Developer ID, and the vendored MediaRemote adapter's whole technique is an end-run around a private framework, so the App Store is not a destination either. The README says plainly how to get a first launch past Gatekeeper.

## 7. Testing

Unit tested: preferences defaults and round trips, including a layout carrying an unknown module; the mapping from stored values to the timings and sizes the app uses; and the clamping that keeps a synthetic notch or a dwell interval from being set to something unusable.

Not unit tested: the window itself, `SMAppService`, and the disk image.
