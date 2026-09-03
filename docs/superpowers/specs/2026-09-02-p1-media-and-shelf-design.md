# NotchDeck P1 — Media and Shelf

**Date:** 2026-09-02
**Status:** Draft
**Parent spec:** [`2026-09-02-notchdeck-design.md`](2026-09-02-notchdeck-design.md)
**Depends on:** P0 (merged) — the notch surface, state machine, gesture accumulator, panel and event monitors.

P1 delivers the two features that carry most of NotchNook's value: a now-playing media player and a drag-and-drop file shelf with an AirDrop target.

---

## 1. Amendments to the parent spec

Two decisions in this phase depart from the parent spec. Both are recorded here rather than silently applied.

**The module registry moves from P2 into P1.** The parent spec schedules `NotchModule` and `ModuleRegistry` for P2. P1 introduces two modules at once, and building them without a shared contract would mean hard-coding both into the shell and rewriting them a phase later. A registry is needed exactly when the second module arrives.

**The ScriptingBridge fallback for reading now-playing state is dropped.** The parent spec lists AppleScript access to Music and Spotify as a fallback behind the MediaRemote adapter. A spike (section 3.1) confirmed the adapter works on macOS 26.6.1 for every player, including browsers, with no TCC prompt. ScriptingBridge would add an Apple Events entitlement, a separate Automation permission prompt, and one code path per player, while covering *fewer* applications than the adapter. It is removed. The fallback for *commands* remains: system HID media keys work everywhere with no permission.

---

## 2. Module hosting

### 2.1 The contract

A module is a self-contained feature that owns some state and contributes views to the notch. The registry knows nothing about any particular module.

Split across two targets so the orderable, persistable part stays testable without SwiftUI:

- `NotchCore` gains `ModuleID` and `ModuleLayout` — the ordered list of module identifiers and which are enabled. Pure value types with persistence and reordering logic.
- `NotchUI` gains the view-producing protocol:

```swift
@MainActor
public protocol NotchModule: AnyObject {
    static var id: ModuleID { get }

    var title: String { get }
    var symbolName: String { get }

    /// Called when the module becomes visible and when it is hidden.
    ///
    /// `deactivate` must release everything that only the open panel needed —
    /// timers, pollers, capture sessions. A module that feeds `peekView()` keeps
    /// that one source running, because the collapsed notch still shows it; the
    /// media module is the example, and it stops only its redraw tick.
    func activate()
    func deactivate()

    func expandedView() -> AnyView

    /// A compact representation for the collapsed notch, or nil when the module
    /// has nothing live to show.
    func peekView() -> AnyView?

    /// True when `peekView()` would return content. Must be cheap and must be
    /// backed by observable state, because the shell reads it on every layout
    /// pass to decide how wide the collapsed notch is.
    var hasLiveContent: Bool { get }
}

public extension NotchModule {
    var id: ModuleID { Self.id }
}
```

### 2.2 Shell changes

`NotchShellView`'s expanded state gains a tab strip listing enabled modules in layout order and hosts the selected module's `expandedView()`. Selection lives in the registry, so all displays show the same tab — consistent with P0's single shared mode.

Modules are app-level singletons; their views are instantiated per surface. Module state must therefore be observable and shared, never owned by a view.

The collapsed notch widens to the peek band whenever `registry.hasLiveContent` is true, and the shell shows the registry's `peekView()`. The state machine stays in `.closed` for this — it never transitions to `.peek`. `.peek` remains the timed mode P3 reserves for live activities (charging, volume), which are entered by an event and expire on their own; a playing track is not an event with a duration, so widening the collapsed notch is driven by content, not by mode.

---

## 3. Media module

### 3.1 What the spike established

A throwaway spike built `ungive/mediaremote-adapter` v0.7.6 (BSD 3-Clause, commit `3ac3d4b`) and exercised it on this machine — macOS 26.6.1, arm64. Findings that the design must respect:

| Finding | Consequence |
|---|---|
| Works fully — `test`, `get`, `stream` and commands. `mediaremoted` accepts the client as `com.apple.perl` with `entitlements=512`. No TCC prompt of any kind. | The adapter is the primary and only source for reading state. |
| No prebuilt release binaries exist; the project builds with CMake, and CMake is not installed here. A direct `clang` build of its 15 `.m` files works. | Vendor upstream **source**, not binaries, and build it with a script that needs only the Xcode toolchain. |
| The framework must carry a code signature or `dlopen` fails. Ad-hoc is sufficient, and `codesign --deep` over the app re-signs the nested framework. The app's own identity is irrelevant — `perl` loads the dylib, not us. | Bundling works under the existing ad-hoc signing story. Never strip the signature. |
| Absolute paths are mandatory; a relative framework path fails at load with exit 1. The `.pl` derives the dylib name from the directory basename, so `X.framework` must contain `X`. | Resolve paths from `Bundle.main` at runtime; never rename the framework directory alone. |
| `stream` emits NDJSON: `{"type":"data","diff":Bool,"payload":{…}}`. First line is a priming empty payload, second is a full snapshot, everything after carries only changed keys. A key that vanished arrives as an explicit `null`. | The client must merge diffs into a running snapshot, and treat explicit null as removal. |
| Artwork is base64 in `artworkData` with `artworkMimeType`, present only in the full snapshot and often late. Both keys absent when unavailable. | Decode once, cache by content identifier, and render an empty state until it arrives. |
| `elapsedTime` never ticks; it is the position as of `timestamp`. On resume the framework restamps `timestamp` **without** resending `elapsedTime`. | Position is `elapsedTime + (now − timestamp) × playbackRate`, driven by `playbackRate` (0 when paused), not the `playing` flag. |
| One logical change arrives as two lines 10–20 ms apart — the `playing` flag, then rate/elapsed/timestamp. | Run the stream with `--debounce=50`, and coalesce anyway. |
| Zero output when nothing changes — no heartbeat, no keepalive, 0 % CPU. | Liveness must be our own concern; silence is indistinguishable from a wedged process. |
| There is no "stopped" event. After playback ends the last track persists indefinitely with `playing:false` and a frozen position. | We need our own staleness policy. |
| The key set is sparse and player-dependent. Only `title` and `playing` are dependable — the adapter's own mandatory-key list (`keys.m`) is `processIdentifier`, `title`, `playing`. `bundleIdentifier` is absent whenever the now-playing process doesn't resolve to an `NSRunningApplication` with a bundle id, which happens for CLI players such as `mpv` even while genuinely playing; the whole output can also be the literal `null` with exit 0. | Every other field, `bundleIdentifier` included, is optional in the model. `null` is a valid, expected snapshot meaning "nothing known". |
| `--micros` replaces the ISO-8601 timestamp with integer epoch microseconds. | Use it. Parsing an integer cannot fail the way a date format can. |
| Commands are one-shot processes, ~18 ms: `send <id>` (0 play, 1 pause, 2 toggle, 4 next, 5 previous) and `seek <microseconds>`. | No long-lived command channel; spawn per command. |
| `test` exits 0 on success and prints nothing. | Use it as a capability probe at launch, and degrade deliberately when it fails. |

### 3.2 Vendoring

`ThirdParty/mediaremote-adapter/` holds the upstream source at the pinned tag, its `LICENSE`, and a `VERSION` file recording tag and commit. `Scripts/build-media-adapter.sh` compiles it into `MediaRemoteAdapter.framework` with `clang` and ad-hoc signs it; `bundle.sh` calls it when the framework is missing or older than the sources, and copies the framework plus `mediaremote-adapter.pl` into the app bundle. The BSD notice is reproduced in the README's acknowledgements.

The `MediaRemoteAdapterTestClient` is bundled too, because it is what makes `test` a trustworthy probe rather than a `get` in disguise.

### 3.3 Structure

- `MediaAdapterProcess` — spawns and supervises the `stream` subprocess, exposes an `AsyncStream` of raw payload lines, restarts with backoff on exit. Behind a protocol so tests never spawn anything.
- `NowPlayingDecoder` — pure. Merges the diff protocol into a running `NowPlaying` snapshot: full snapshots replace, diffs merge, explicit nulls remove, the priming empty payload is ignored, and a literal `null` document clears everything. This is where the sparse schema is absorbed, and it is the most heavily tested piece in the phase.
- `NowPlaying` — the model. Only `isPlaying` and `title` are non-optional; `bundleIdentifier` is absent for players without a resolvable bundle.
- `PlaybackPosition` — pure. `position(at:)` implements the interpolation rule, clamped to `duration` when known.
- `MediaCommands` — sends `send`/`seek` through the adapter, falling back to HID media keys when the adapter is unavailable.
- `MediaModule` — the `NotchModule`, owning the above and publishing state to views.

**Lifecycle:** the `stream` subprocess must not outlive the app, and nothing does that for free. While a track plays the adapter writes constantly and dies of `SIGPIPE` the moment its parent is gone; idle, it writes nothing — the adapter's "zero output when nothing changes" — so it never notices and survives reparented to launchd indefinitely. `AsyncStream`'s `onTermination` does not help either: it fires only when the stream finishes or the consuming task is cancelled, and a process exit does neither.

Starting the stream and activating the module are deliberately separate. `MediaModule.startStreaming()` starts only the adapter stream and is idempotent; the app calls it once at launch, before the panel is ever opened, so the collapsed peek has something to show from the start. `activate()` calls `startStreaming()` and additionally starts the once-a-second redraw tick that advances the scrubber — the registry calls it only while the panel is open, and `deactivate()` stops the tick alone, leaving the stream running for the peek.

The shutdown has two halves. Graceful exits reach `applicationWillTerminate`, which calls `MediaModule.shutdown()`: it cancels the stream, tick and staleness tasks and calls `stop()` on the live `PerlAdapterStream` synchronously, because that delegate callback is the last main-actor turn and a mere task cancellation would only take effect on a turn that never comes. A menu quit gets there on its own; `SIGTERM` does not — AppKit installs no handler, so the default disposition kills the process before any delegate method runs, exactly like `SIGKILL`. The delegate therefore installs a `DispatchSource` signal source that turns `SIGTERM` into `NSApp.terminate`, so `pkill -x NotchDeck` and a launchd stop take the graceful path too. That handler still runs on the main queue, though: a wedged main thread never dispatches it, so `SIGTERM` against a hung instance does nothing and only `SIGKILL` actually ends it. Ungraceful exits — `SIGKILL`, a crash, or a `SIGTERM` a wedged main thread never got to handle — cannot run anything, so every launch first awaits `AdapterReaper.reapOrphans(of:)` before the probe: a `pkill -f` on the bundle's own absolute script path (regex-escaped), which matches only adapters started from *this* bundle and leaves other apps' copies alone. Exit 0 (killed something) and 1 (nothing matched) are both success; anything else is logged and ignored, since the worst outcome is the orphan we already had.

### 3.4 Behaviour

**Expanded view:** artwork (or a placeholder), title, artist or album, a draggable scrubber, and previous / play-pause / next. Scrubbing seeks on release, not continuously. The source app's icon and elapsed/remaining time labels are deferred to P4 polish.

**Peek view:** artwork thumbnail on one side of the notch and an animated level indicator on the other — the same band shape P0's `peek` mode draws, but reached differently. `NotchModule` exposes an observable `hasLiveContent` predicate; `ModuleRegistry.hasLiveContent` is true when any visible module offers content. While the notch is `.closed` and that is true, `NotchViewModel.targetSize` returns the peek band's size and `NotchShellView` renders the registry's `peekView` — the hover region follows, because it derives from `targetSize`. The state machine never leaves `.closed` for this. `.peek(PeekPayload)` is the *timed* live-activity mode reserved for P3 (charging, volume): it is entered by a `.liveActivity` event and expires on its own. A playing track is not an event with a duration; it is live content that persists for as long as the module offers it, so faking it through `.liveActivity` would either time out under a playing track or need constant re-sending. The media module reports `hasLiveContent` as "a track is known and not stale".

**Gestures:** P0's accumulator already classifies horizontal swipes into `.left` and `.right`, which the notch reducer deliberately ignores. `NotchEventMonitor` gains a second callback for horizontal swipes over a surface, which the app forwards to the media module as next/previous. The notch state machine stays about the notch.

**Staleness:** a track whose `playbackRate` is 0 and whose last update is older than a threshold stops being shown in the peek. The expanded view keeps showing it, so the user can still resume. This is the policy the adapter does not provide.

**Degradation:** if the `test` probe fails at launch, the module still loads and still sends commands via HID keys, but shows an explanatory empty state instead of fabricating a track.

---

## 4. Shelf module

### 4.1 Structure

- `ShelfItem` — a stored reference: security-scoped bookmark, display name, file size, content type, date added, and a resolved-availability flag.
- `ShelfStore` — pure logic over an injected persistence and file-resolution seam: add, remove, reorder, de-duplicate by resolved path, cap the item count, and mark items whose bookmark no longer resolves as unavailable rather than dropping them.
- `ShelfModule` — the `NotchModule`. Returns nil from `peekView()`.

Persistence is a JSON document in Application Support, written atomically. Bookmarks are the storage mechanism precisely because they survive the file being moved or renamed; an item is marked unavailable only when the bookmark genuinely cannot resolve, and the item view then offers to remove it.

### 4.2 Drag in

`NotchContainerView` registers dragged types and reports drag-enter and drag-exit. P0's reducer already handles `.dragEntered` and `.dragExited`; the new behaviour is that entering also selects the shelf tab, so a dragged file lands on a visible drop target. Dropping adds every dropped URL to the store.

### 4.3 Drag out

Items drag back out to Finder and other applications using `NSFilePromiseProvider`, so a drag that ends in a file-consuming target gets a real file, and one that ends nowhere costs nothing.

### 4.4 AirDrop

A distinct drop target inside the shelf panel hands the dropped URLs — or the currently selected items — to `NSSharingService(named: .sendViaAirDrop)`. When the service reports itself unavailable for the given items, the target says so instead of failing silently.

### 4.5 Item actions

Per item: reveal in Finder, Quick Look, copy, remove. Whole shelf: clear all, behind a confirmation.

---

## 5. Testing

Unit tested, pure, no AppKit and no subprocesses:

- `NowPlayingDecoder` — priming line, full snapshot, diff merge, explicit-null removal, literal `null` document, sparse payloads missing every optional key, malformed JSON, a diff arriving before any snapshot, and artwork appearing only later
- `PlaybackPosition` — interpolation while playing, frozen while paused, the restamped-timestamp-without-elapsed case the spike found, clamping at duration, and a missing duration
- `ShelfStore` — add, remove, reorder, de-duplication, cap enforcement, persistence round-trip, stale bookmark marked unavailable rather than dropped
- `ModuleLayout` — ordering, enable and disable, persistence, and an unknown module ID surviving a round trip
- `MediaCommands` — the right command ID for each transport action, and the HID fallback selection

Behind protocols with fakes: the adapter subprocess, the clock, the file system and bookmark resolution, `NSSharingService`, and the pasteboard.

Not unit tested, verified by hand: drag and drop into a non-activating panel, file promises, AirDrop delivery, artwork rendering, scrubber feel.

---

## 6. Risks

**Drag and drop into a panel that is never key.** P0 deliberately made the notch panel non-activating with `canBecomeKey` false. Drag destinations should not require key status, and `acceptsFirstMouse` is already set — but this is unverified, and the whole shelf depends on it. **P1b begins with a spike that proves a file can be dropped onto, and dragged out of, a panel configured exactly like `NotchPanel`.** If it cannot, the panel configuration has to change and that must be discovered before anything is built on it.

**The adapter rests on Apple's system Perl.** The technique works because `/usr/bin/perl` is reported as `com.apple.perl`. Apple has deprecated system Perl for years. If it is removed, or the entitlement stops being granted, reading now-playing state dies at once for every app using this approach. The mitigation is already in the design: probe with `test`, and degrade to commands-only rather than crashing.

**Artwork memory.** Base64 artwork arrives inline on every full snapshot. Decode once, cache by `contentItemIdentifier`, and never hold more than the current track's image.

---

## 7. Delivery

P1 splits into two plans, each ending in a runnable app.

**P1a — Module hosting and media.** The `NotchModule` contract, `ModuleLayout`, the registry, the tab strip, vendoring and building the adapter, the decoder and position maths, the subprocess supervisor, the expanded player, the peek view, transport commands and swipe gestures.

**P1b — Shelf and AirDrop.** The drag-and-drop spike first, then `ShelfStore`, the drop target, item views and actions, drag-out via file promises, and the AirDrop target.
