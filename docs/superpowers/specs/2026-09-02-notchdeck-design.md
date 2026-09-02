# NotchDeck — Design

**Date:** 2026-09-02
**Status:** Approved
**Goal:** A macOS app that turns the MacBook notch (and a synthetic notch on displays without one) into an interactive utility surface, covering the full feature set of NotchNook 1.6.x, minus weather.

---

## 1. Product scope

### 1.1 Feature parity target

| Area | Requirement |
|---|---|
| Notch shell | Collapsed / peek / open states, hover to expand, scroll to open, click to pin, click-away and Esc to close, morphing rounded shape, click-through outside the visible shape |
| Displays | One notch surface per screen; real notch geometry on built-in displays, synthetic notch on notchless/external displays; per-screen enable policy |
| Media | Now-playing peek beside the notch (artwork + animated visualizer), expanded player with artwork, title/artist, scrubber, play/pause, prev/next, volume, output device name; two-finger horizontal swipe to change track |
| Shelf | Drag files onto the notch to store them; drag out to Finder/apps; persistent across launches; per-item preview, remove, reveal in Finder, quick look |
| AirDrop | Dedicated drop zone that hands dropped URLs to the system AirDrop sharing service |
| Calendar | Today/upcoming events, all-day handling, join-meeting link detection, day navigation |
| Shortcuts | List user shortcuts, pin favourites, run from the panel |
| Mirror | Live front-camera preview inside the panel |
| Clipboard | History of recent copies (text, URL, image) with pinning, search, exclusions, size cap |
| Timer | Pomodoro with work/break cycles, notch peek countdown, sound on completion |
| Stats | Battery (level, charging, time remaining), CPU, memory, network throughput |
| Live activities | Charging connected/disconnected, volume change, brightness change, Bluetooth/AirPods connect, Focus mode change, file drop confirmation, timer completion |
| System HUD | Replace macOS volume/brightness OSD with the notch peek (suppress `OSDUIHelper`), individually switchable |
| Settings | Per-module enable/disable and ordering, notch geometry tuning, gesture toggles, appearance, launch at login, permission status panel |

### 1.2 Explicitly out of scope

- Weather widget (dropped by decision — WeatherKit needs a paid Apple Developer account).
- Licensing, DRM, subscriptions, device limits.
- Notes / to-dos widgets (NotchNook lists them as "coming soon", not shipped parity).
- Mac App Store distribution and notarization.

---

## 2. Architecture

### 2.1 Build system

A SwiftPM workspace: library modules plus one thin executable. `Scripts/bundle.sh` assembles `NotchDeck.app` from the built executable, `Resources/Info.plist`, entitlements, and assets, then codesigns it.

Rationale: `swift test` runs headless and fast, business logic stays free of AppKit, and there is no `.pbxproj` to corrupt. Cost: the bundle is assembled by a script instead of Xcode.

### 2.2 Module layout

```
notchdeck/
├─ Package.swift
├─ Sources/
│  ├─ NotchDeckApp/          @main, AppDelegate, dependency wiring, menu bar item
│  ├─ NotchCore/             state machine, gesture router, module registry, event bus
│  ├─ NotchWindow/           NSPanel engine, screen geometry, per-screen surfaces
│  ├─ NotchUI/               SwiftUI shell, shape morphing, tab bar, shared components
│  ├─ Modules/
│  │  ├─ MediaModule/
│  │  ├─ ShelfModule/
│  │  ├─ CalendarModule/
│  │  ├─ ShortcutsModule/
│  │  ├─ MirrorModule/
│  │  ├─ ClipboardModule/
│  │  ├─ TimerModule/
│  │  └─ StatsModule/
│  ├─ LiveActivities/        system event sources feeding peek presentations
│  ├─ SystemHUD/             OSD suppression and media key interception
│  ├─ Settings/              preferences store and settings window
│  └─ Support/               logging, permissions, defaults, file helpers
├─ Tests/                    one test target per testable module
├─ Resources/                Info.plist, entitlements, assets, vendored adapter
└─ Scripts/                  bundle.sh, make-dev-cert.sh, run.sh
```

Dependency direction is strictly one way: `NotchDeckApp` → `Modules`/`LiveActivities`/`Settings` → `NotchUI` → `NotchWindow` → `NotchCore` → `Support`. `NotchCore` imports nothing from AppKit.

### 2.3 The module contract

Every widget conforms to a single protocol so the core never learns about individual features:

```swift
protocol NotchModule: AnyObject {
    static var identifier: ModuleID { get }
    var title: String { get }
    var symbolName: String { get }
    var requiredPermissions: [Permission] { get }

    func activate()      // called when the module becomes visible
    func deactivate()    // called when hidden; must release cameras, timers, pollers

    @MainActor func expandedView() -> AnyView
    @MainActor func peekView() -> AnyView?   // nil when the module has no live state
}
```

`ModuleRegistry` owns instances, honours the user's enable/order preferences, and drives the tab bar. Adding a widget means adding one type and registering it; no core changes.

### 2.4 State machine

`NotchState` is a pure value type in `NotchCore`:

```
closed ──hover(dwell)──▶ open
closed ──scroll(down)──▶ open
closed ──liveEvent────▶ peek(event) ──timeout──▶ closed
closed ──dragEnter────▶ open(shelf)
open   ──hoverExit(grace)──▶ closed
open   ──click──▶ pinned ──clickAway|esc──▶ closed
peek   ──hover──▶ open
```

Transitions are driven by a `NotchEvent` enum. The reducer is `(NotchState, NotchEvent) -> NotchState` with no side effects, which makes the whole interaction model unit-testable without a window.

Timing constants (hover dwell, exit grace, peek duration) are injected, not hard-coded, so tests run instantly.

### 2.5 Window engine

- `ScreenGeometry` resolves the notch rect from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. When a screen reports no notch, it synthesizes one of the user-configured size, centred at the top.
- One `NotchPanel` per participating screen. Configuration: `NSPanel(.nonactivatingPanel, .borderless)`, level above the status bar, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isMovable = false`, transparent background.
- The panel is always sized to the maximum expanded bounds. The visible surface is a masked squircle that animates between state sizes; `hitTest` returns `nil` for points outside the current mask so clicks fall through to apps underneath.
- Screen configuration changes (`NSApplication.didChangeScreenParametersNotification`) rebuild the panel set.
- A global `NSEvent` monitor for `.mouseMoved` and `.scrollWheel` feeds the gesture router; the router converts raw events into `NotchEvent`s and is itself pure.
- Drag-to-open works while the app is inactive because the panel registers dragged types and the drop-catcher view stays mounted in the collapsed state.

---

## 3. Risky mechanisms and how they are handled

| Concern | Approach | Fallback |
|---|---|---|
| Now-playing **reads** — MediaRemote is entitlement-gated since macOS 15.4 | Vendor `ungive/mediaremote-adapter`: the entitled system `/usr/bin/perl` loads a helper framework and streams now-playing JSON on stdout; a `MediaSource` actor parses it | ScriptingBridge to Music.app and Spotify; then a "no player" empty state |
| Now-playing **controls** | System-defined HID events (`NX_KEYTYPE_PLAY`, `NX_KEYTYPE_NEXT`, `NX_KEYTYPE_PREVIOUS`) — no permissions, works with every player | — |
| Shelf files | `NSItemProvider` with file promises for drag-out; bookmarks persisted in Application Support with security-scoped access | Copy into an app-owned staging directory when a bookmark goes stale |
| AirDrop | `NSSharingService(named: .sendViaAirDrop)` invoked with the dropped URLs | Generic share sheet |
| Calendar | EventKit with full-access request | Empty state with a "grant access" button |
| Shortcuts | `shortcuts list` to enumerate, `shortcuts run <name>` to execute | — |
| Camera mirror | AVFoundation capture session, started only while the module is active | Empty state with a "grant access" button |
| Clipboard | Poll `NSPasteboard.general.changeCount` at ~0.3s; skip items marked transient/concealed and app exclusions | — |
| System HUD replacement | Intercept media/brightness keys and suspend `OSDUIHelper` while the feature is on; restore on quit | Feature is off by default and documented as fragile across macOS updates |
| Battery and stats | IOKit power sources, `host_statistics64`, network interface counters | — |
| Accessibility permission | Required for the global event monitor; requested on first launch with a clear explanation | The app still works via panel-local tracking, with reduced gesture support |

### 3.1 Code signing

The machine has no Developer ID identity. Ad-hoc signing changes the code hash on every rebuild, which makes macOS re-prompt for Camera, Calendar and Accessibility permissions after each build.

`Scripts/make-dev-cert.sh` creates a self-signed code-signing certificate in the login keychain once. `bundle.sh` signs with it, giving a stable designated requirement so TCC grants survive rebuilds. The README documents this as a required first step.

---

## 4. Testing strategy

Test-driven, per the project convention. Tests are written in English.

Unit tested directly (pure Swift, no AppKit):
- `NotchCore` — state reducer, every transition and timing edge case
- `ScreenGeometry` — notch rect resolution, synthetic notch placement, multi-screen layouts
- Gesture router — scroll and swipe classification, thresholds, direction
- `ShelfStore` — add, remove, reorder, persistence round-trip, stale bookmark recovery
- `ClipboardStore` — dedupe, cap enforcement, pinning, exclusions
- `TimerModule` — pomodoro cycle progression
- Now-playing JSON parsing — malformed input, missing fields, artwork decoding
- Preferences store — defaults, migration, per-module ordering

Behind protocols with fakes: `NSPasteboard`, EventKit, AVFoundation, IOKit, process launching, the media adapter subprocess, and the clock.

Not unit tested (verified manually per phase): panel levels and hit-testing, animation feel, TCC prompts, OSD suppression.

---

## 5. Delivery phases

Each phase ends with a runnable app. Each gets its own implementation plan.

**P0 — Skeleton**
Repo, `Package.swift`, `bundle.sh`, `make-dev-cert.sh`, menu bar item with quit and settings, notch panel on every screen that expands on hover and closes on exit, click-through outside the shape, synthetic notch on notchless displays.
Tests: state reducer, screen geometry, gesture router.

**P1 — Core value**
Media module (peek with artwork and visualizer, expanded player with scrubber and transport, swipe to change track) and Shelf module (drag in, drag out, persistence, previews, AirDrop zone).
Tests: now-playing parsing, shelf store.

**P2 — Widgets**
Calendar, Shortcuts, Mirror, Clipboard, Timer, Stats, plus the tab bar and module registry preferences.
Tests: clipboard store, timer cycles.

**P3 — Live activities and HUD**
Charging, volume, brightness, Bluetooth/AirPods, Focus, drop confirmation, timer completion; `OSDUIHelper` suppression with per-event toggles.

**P4 — Settings and release**
Full settings window, launch at login, notch geometry tuning per screen, permission status panel, DMG build script, README.

---

## 6. Non-functional requirements

- **Minimum OS:** macOS 26.0. Swift 6 language mode, strict concurrency.
- **Idle cost:** no polling loops when the notch is closed and no module is active; the clipboard poller runs only while the clipboard module is enabled.
- **Privacy:** no network access except what a user-enabled module explicitly needs; nothing is transmitted off device.
- **Language:** all code, comments, docs, commits and UI strings in English.
- **Failure mode:** a module that throws or loses its permission degrades to an empty state with a recovery action; it never takes down the notch shell.
