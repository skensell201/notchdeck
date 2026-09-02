# NotchDeck P1a — Module Hosting and Media Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the P0 skeleton into a working now-playing player: a tabbed module shell hosting a media module that reads live state from every macOS player, shows artwork, title, a moving scrubber and transport controls in the expanded notch, an artwork-and-visualiser peek while collapsed, and next/previous on a two-finger horizontal swipe.

**Architecture:** Reading now-playing state goes through a vendored copy of `ungive/mediaremote-adapter`, built from source into a code-signed framework that the entitled system `/usr/bin/perl` loads on our behalf. A supervised subprocess streams NDJSON; a pure decoder merges its diff protocol into a snapshot; a pure function interpolates playback position between updates. Everything that can be a value type is one, and the subprocess, clock and command channel sit behind protocols so the whole module is testable without spawning anything.

**Tech Stack:** Swift 6 (language mode v6, strict concurrency), SwiftPM, swift-testing, SwiftUI, `Foundation.Process`, `ungive/mediaremote-adapter` v0.7.6 (BSD 3-Clause).

**Spec:** [`docs/superpowers/specs/2026-09-02-p1-media-and-shelf-design.md`](../specs/2026-09-02-p1-media-and-shelf-design.md)

---

## Background the implementer needs

P0 shipped and is merged. What exists:

- `NotchCore` — `NotchReducer` (pure state machine over `closed` / `peek` / `open` / `pinned`), `NotchController` (owns state, turns effects into timers via an injected main-actor `NotchScheduler`), `ScrollAccumulator` (raw scroll deltas → at most one `ScrollDirection` per swipe, phases `began`/`changed`/`ended`/`momentum`/`discrete`), `NotchResolver` (screen → notch rect). 62 tests.
- `NotchUI` — `NotchShape`, `NotchViewModel` (per-surface geometry and mode; `targetSize`, `maximumSize`, `surfaceRectInScreen`, `presentedRectInView`), `NotchShellView` (renders the shape, currently with placeholder text).
- `NotchWindow` — `NotchPanel`, `NotchContainerView`, `NotchSurface`, `NotchSurfaceManager`, `NotchEventMonitor`.
- `NotchDeckApp` — `AppDelegate` wiring a controller, a surface manager and an event monitor, plus a menu bar item.
- `Scripts/bundle.sh` assembles and ad-hoc signs `build/NotchDeck.app`; `Scripts/run.sh` builds and launches it.

The notch reducer deliberately ignores `.scrolled(.left)` and `.scrolled(.right)`. Horizontal swipes are the media module's business and reach it by a separate route added in Task 11.

**Everything the spike established about the adapter is in section 3.1 of the spec. Read it before Task 4.** The protocol details that bite — the priming line, diffs carrying only changed keys, explicit nulls meaning removal, a position that never ticks, a timestamp restamped without a matching elapsed value, and no "stopped" event ever — are the reason Tasks 5 and 6 are as heavily tested as they are.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Sources/NotchCore/ModuleID.swift` | Stable module identity |
| `Sources/NotchCore/ModuleLayout.swift` | Which modules exist, their order, which are enabled |
| `Sources/NotchUI/NotchModule.swift` | The view-producing module protocol |
| `Sources/NotchUI/ModuleRegistry.swift` | Holds modules, honours the layout, owns tab selection |
| `Sources/NotchUI/ModuleTabStrip.swift` | The tab strip in the expanded panel |
| `Sources/Media/NowPlaying.swift` | The snapshot model |
| `Sources/Media/PayloadDelta.swift` | Decoding one stream payload, distinguishing absent from null |
| `Sources/Media/NowPlayingDecoder.swift` | Merges the diff protocol into a snapshot |
| `Sources/Media/PlaybackPosition.swift` | Interpolates position between updates |
| `Sources/Media/MediaCommands.swift` | Transport commands, adapter first, HID keys as fallback |
| `Sources/Media/MediaAdapterProcess.swift` | Spawns and supervises the streaming subprocess |
| `Sources/Media/MediaModule.swift` | The `NotchModule`, owning the above |
| `Sources/Media/MediaPlayerView.swift` | Expanded player UI |
| `Sources/Media/MediaPeekView.swift` | Collapsed artwork-and-visualiser UI |
| `ThirdParty/mediaremote-adapter/` | Vendored upstream source, LICENSE, VERSION |
| `Scripts/build-media-adapter.sh` | Builds the vendored source into a signed framework |
| `Tests/NotchCoreTests/ModuleLayoutTests.swift` | Layout ordering and persistence |
| `Tests/MediaTests/*` | Decoder, position, commands |

`Media` is a new library target depending on `NotchCore` and `NotchUI`. `NotchDeckApp` gains a dependency on it.

---

## Task 1: Module identity and layout

**Files:**
- Create: `Sources/NotchCore/ModuleID.swift`
- Create: `Sources/NotchCore/ModuleLayout.swift`
- Test: `Tests/NotchCoreTests/ModuleLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import NotchCore

@Suite("Module layout")
struct ModuleLayoutTests {
    private let media = ModuleID("media")
    private let shelf = ModuleID("shelf")
    private let clipboard = ModuleID("clipboard")

    @Test("a layout lists its modules in the order it was given")
    func preservesOrder() {
        let layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [])

        #expect(layout.enabledOrder == [media, shelf, clipboard])
    }

    @Test("disabled modules keep their place in the order but drop out of the enabled list")
    func disabledDropOut() {
        let layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [shelf])

        #expect(layout.enabledOrder == [media, clipboard])
        #expect(layout.order == [media, shelf, clipboard])
    }

    @Test("moving a module changes its position without disturbing the rest")
    func moving() {
        var layout = ModuleLayout(order: [media, shelf, clipboard], disabled: [])

        layout.move(clipboard, to: 0)

        #expect(layout.order == [clipboard, media, shelf])
    }

    @Test("moving a module that is not in the layout does nothing")
    func movingUnknownIsIgnored() {
        var layout = ModuleLayout(order: [media, shelf], disabled: [])

        layout.move(clipboard, to: 0)

        #expect(layout.order == [media, shelf])
    }

    @Test("registering a module appends it once, however many times it is registered")
    func registerIsIdempotent() {
        var layout = ModuleLayout(order: [media], disabled: [])

        layout.register(shelf)
        layout.register(shelf)

        #expect(layout.order == [media, shelf])
    }

    @Test("a module the user disabled stays disabled when it is registered again")
    func registerPreservesDisabledState() {
        var layout = ModuleLayout(order: [media, shelf], disabled: [shelf])

        layout.register(shelf)

        #expect(layout.enabledOrder == [media])
    }

    @Test("a layout survives a JSON round trip, including modules this build does not know")
    func codableRoundTrip() throws {
        let original = ModuleLayout(order: [media, shelf, ModuleID("from-the-future")], disabled: [shelf])

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ModuleLayout.self, from: data)

        #expect(restored == original)
    }

    @Test("the first enabled module is the default selection, and nil when everything is disabled")
    func defaultSelection() {
        #expect(ModuleLayout(order: [media, shelf], disabled: [media]).defaultSelection == shelf)
        #expect(ModuleLayout(order: [media], disabled: [media]).defaultSelection == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ModuleLayoutTests`
Expected: FAIL — `cannot find 'ModuleID' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/NotchCore/ModuleID.swift`:

```swift
/// A module's stable identity. It is persisted, so it must not change when a
/// module is renamed in the UI.
public struct ModuleID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
```

`Sources/NotchCore/ModuleLayout.swift`:

```swift
/// Which modules the panel shows, in what order, and which the user turned off.
///
/// The order deliberately keeps disabled modules in place so that re-enabling one
/// puts it back where the user left it. Unknown identifiers are preserved through
/// a round trip so that downgrading a build does not discard a newer module's
/// position.
public struct ModuleLayout: Equatable, Sendable, Codable {
    public private(set) var order: [ModuleID]
    public private(set) var disabled: Set<ModuleID>

    public init(order: [ModuleID] = [], disabled: Set<ModuleID> = []) {
        self.order = order
        self.disabled = disabled
    }

    public var enabledOrder: [ModuleID] {
        order.filter { !disabled.contains($0) }
    }

    public var defaultSelection: ModuleID? {
        enabledOrder.first
    }

    /// Adds a module the build knows about. Registering an already-known module
    /// leaves its position and enabled state untouched.
    public mutating func register(_ id: ModuleID) {
        guard !order.contains(id) else { return }
        order.append(id)
    }

    public mutating func move(_ id: ModuleID, to index: Int) {
        guard let current = order.firstIndex(of: id) else { return }
        order.remove(at: current)
        order.insert(id, at: min(max(index, 0), order.count))
    }

    public mutating func setEnabled(_ enabled: Bool, for id: ModuleID) {
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter ModuleLayoutTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchCore/ModuleID.swift Sources/NotchCore/ModuleLayout.swift Tests/NotchCoreTests/ModuleLayoutTests.swift
git commit -m "feat: add module identity and layout"
```

---

## Task 2: The module contract and registry

**Files:**
- Create: `Sources/NotchUI/NotchModule.swift`
- Create: `Sources/NotchUI/ModuleRegistry.swift`

No unit tests: `ModuleRegistry` is `@MainActor` and holds `AnyView`-producing objects, so its only real logic is the layout it delegates to, which Task 1 tests. Verified through the app.

- [ ] **Step 1: Write the protocol**

`Sources/NotchUI/NotchModule.swift`:

```swift
import NotchCore
import SwiftUI

/// A self-contained feature that contributes views to the notch.
///
/// A module is an app-level singleton: its state is shared, and its views are
/// instantiated once per screen surface. State must therefore live on the module
/// (observable), never in a view.
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
}

public extension NotchModule {
    nonisolated var id: ModuleID { Self.id }
}
```

- [ ] **Step 2: Write the registry**

`Sources/NotchUI/ModuleRegistry.swift`:

```swift
import NotchCore
import Observation

/// Owns the app's modules, honours the user's layout, and tracks which tab is
/// showing. Shared across every screen surface, so all displays agree.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var layout: ModuleLayout
    public private(set) var selection: ModuleID?

    private var modules: [ModuleID: any NotchModule] = [:]
    private var activated: ModuleID?

    public init(layout: ModuleLayout = ModuleLayout()) {
        self.layout = layout
    }

    public func register(_ module: any NotchModule) {
        modules[module.id] = module
        layout.register(module.id)
        if selection == nil {
            selection = layout.defaultSelection
        }
    }

    public var visibleModules: [any NotchModule] {
        layout.enabledOrder.compactMap { modules[$0] }
    }

    public func module(_ id: ModuleID) -> (any NotchModule)? {
        modules[id]
    }

    public var selectedModule: (any NotchModule)? {
        guard let selection else { return nil }
        return modules[selection]
    }

    public func select(_ id: ModuleID) {
        guard modules[id] != nil, !layout.disabled.contains(id) else { return }
        selection = id
    }

    /// Activates the selected module and deactivates whichever was active before,
    /// so exactly one module holds live resources at a time.
    public func setPanelVisible(_ visible: Bool) {
        let wanted = visible ? selection : nil
        guard wanted != activated else { return }

        if let activated, let module = modules[activated] {
            module.deactivate()
        }
        activated = wanted
        if let wanted, let module = modules[wanted] {
            module.activate()
        }
    }

    /// The first visible module offering live content for the collapsed notch.
    public var peekProvider: (any NotchModule)? {
        visibleModules.first { $0.peekView() != nil }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/NotchUI/NotchModule.swift Sources/NotchUI/ModuleRegistry.swift
git commit -m "feat: add the module contract and registry"
```

---

## Task 3: Tab strip and module hosting in the shell

**Files:**
- Create: `Sources/NotchUI/ModuleTabStrip.swift`
- Modify: `Sources/NotchUI/NotchShellView.swift`
- Modify: `Sources/NotchUI/NotchViewModel.swift`

The shell currently renders placeholder text. It now renders the selected module, with a tab strip along the top of the expanded panel clearing the physical notch.

- [ ] **Step 1: Write the tab strip**

`Sources/NotchUI/ModuleTabStrip.swift`:

```swift
import SwiftUI

public struct ModuleTabStrip: View {
    private let registry: ModuleRegistry

    public init(registry: ModuleRegistry) {
        self.registry = registry
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(registry.visibleModules, id: \.id) { module in
                let isSelected = registry.selection == module.id
                Button {
                    registry.select(module.id)
                } label: {
                    Image(systemName: module.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(isSelected ? 0.18 : 0))
                        )
                        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
                }
                .buttonStyle(.plain)
                .help(module.title)
            }
        }
    }
}
```

- [ ] **Step 2: Give the view model the registry**

In `NotchViewModel`, add a stored `public let registry: ModuleRegistry` and take it in `init` as the first parameter. Every existing call site must pass it.

- [ ] **Step 3: Render modules in the shell**

Replace `NotchShellView`'s `content` property with:

```swift
    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .closed:
            EmptyView()
        case .peek:
            peekContent
        case .open, .pinned:
            expandedContent
        }
    }

    @ViewBuilder
    private var peekContent: some View {
        if let peek = model.registry.peekProvider?.peekView() {
            peek
                .padding(.horizontal, model.closedFlare + 4)
                .frame(maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            ModuleTabStrip(registry: model.registry)
                .frame(height: model.metrics.rect.height)
            if let module = model.registry.selectedModule {
                module.expandedView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No modules enabled")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .transition(.opacity)
    }
```

The tab strip occupies a band the height of the physical notch, so it sits either side of the camera housing rather than under it.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: succeeds. `swift test` still green.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchUI
git commit -m "feat: host modules in the notch shell behind a tab strip"
```

---

## Task 4: Vendor and build the MediaRemote adapter

**Files:**
- Create: `ThirdParty/mediaremote-adapter/` (upstream source, `LICENSE`, `VERSION`)
- Create: `Scripts/build-media-adapter.sh`
- Modify: `Scripts/bundle.sh`
- Modify: `README.md`

Reading now-playing state requires Apple's private `MediaRemote`, which since macOS 15.4 rejects unentitled clients. The adapter sidesteps this by having the entitled system `/usr/bin/perl` load a helper framework. A spike verified the whole approach on macOS 26.6.1 — see spec section 3.1.

- [ ] **Step 1: Vendor the source**

```bash
cd /tmp
git clone --depth 1 --branch v0.7.6 https://github.com/ungive/mediaremote-adapter.git mra
cd mra && git rev-parse HEAD   # must be 3ac3d4bdf862c7b5399b4fba4df5689f5c38609a
```

Copy into `ThirdParty/mediaremote-adapter/`: the Objective-C sources and headers, `mediaremote-adapter.pl`, and `LICENSE`. Do not copy `.git`, CI config, or build output. Write `ThirdParty/mediaremote-adapter/VERSION` containing the tag and the commit hash.

- [ ] **Step 2: Write the build script**

`Scripts/build-media-adapter.sh`:

```bash
#!/usr/bin/env bash
# Builds the vendored mediaremote-adapter sources into a code-signed framework.
#
# Upstream builds with CMake; we use clang directly so the only requirement is
# the Xcode toolchain. The framework MUST be signed or /usr/bin/perl cannot
# dlopen it, and the directory name must match the binary name inside it —
# the .pl script derives one from the other.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/mediaremote-adapter"
OUT="$ROOT/build/MediaRemoteAdapter.framework"
NAME="MediaRemoteAdapter"

rm -rf "$OUT"
mkdir -p "$OUT/Versions/A/Resources"

clang -dynamiclib -fobjc-arc -O2 \
    -arch arm64 -mmacosx-version-min=26.0 \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -I "$SRC/include" \
    -o "$OUT/Versions/A/$NAME" \
    "$SRC"/src/*.m

cat > "$OUT/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundleIdentifier</key>
    <string>com.skensell.notchdeck.MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>0.7.6</string>
</dict>
</plist>
PLIST

ln -sfn A "$OUT/Versions/Current"
ln -sfn "Versions/Current/$NAME" "$OUT/$NAME"
ln -sfn Versions/Current/Resources "$OUT/Resources"

codesign --force --sign - "$OUT"
echo "$OUT"
```

Adjust the source and include paths to match the vendored layout. If upstream's sources need additional frameworks, the linker will say so — add them and note it.

- [ ] **Step 3: Verify the built framework actually works**

```bash
chmod +x Scripts/build-media-adapter.sh
./Scripts/build-media-adapter.sh
/usr/bin/perl "$PWD/ThirdParty/mediaremote-adapter/mediaremote-adapter.pl" \
  "$PWD/build/MediaRemoteAdapter.framework" get --micros --no-artwork
```

Expected: a single line of JSON with a playing track, or the literal `null` when nothing is playing. Both are success; exit code 0 is what matters. Paths must be absolute — a relative framework path fails at load.

If this does not work, stop and report. Everything after this task depends on it.

- [ ] **Step 4: Copy the adapter into the app bundle**

In `Scripts/bundle.sh`, after the executable is copied and before signing:

```bash
"$ROOT/Scripts/build-media-adapter.sh" >&2
mkdir -p "$APP/Contents/Frameworks"
cp -R "$ROOT/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/ThirdParty/mediaremote-adapter/mediaremote-adapter.pl" "$APP/Contents/Resources/"
```

The existing `codesign --force --sign "$IDENTITY" "$APP"` must become `codesign --force --deep --sign "$IDENTITY" "$APP"` so the nested framework is re-signed with the bundle. Verify afterwards that `codesign --verify --deep` passes and that the same `perl` invocation works against the copy inside `build/NotchDeck.app`.

- [ ] **Step 5: Record the license**

Add an "Acknowledgements" section to `README.md` naming `ungive/mediaremote-adapter` v0.7.6, its BSD 3-Clause license, and the path to the vendored `LICENSE`. BSD clause 2 requires the notice to travel with binary distributions.

- [ ] **Step 6: Commit**

```bash
git add ThirdParty Scripts/build-media-adapter.sh Scripts/bundle.sh README.md
git commit -m "build: vendor and build the MediaRemote adapter"
```

---

## Task 5: The now-playing model and stream decoder

**Files:**
- Create: `Sources/Media/NowPlaying.swift`
- Create: `Sources/Media/PayloadDelta.swift`
- Create: `Sources/Media/NowPlayingDecoder.swift`
- Modify: `Package.swift` (add the `Media` target and `MediaTests`)
- Test: `Tests/MediaTests/NowPlayingDecoderTests.swift`

This is the most defect-prone piece in the phase, because the wire protocol is sparse, diff-based, and distinguishes "absent" from "explicitly cleared".

The stream emits one JSON object per line: `{"type":"data","diff":Bool,"payload":{…}}`. The first line is a priming empty payload. `diff:false` payloads are complete snapshots; `diff:true` payloads carry only the keys that changed, and a key that has gone away arrives as an explicit `null`.

- [ ] **Step 1: Add the target to `Package.swift`**

```swift
        .target(name: "Media", dependencies: ["NotchCore", "NotchUI", "Support"]),
```
and
```swift
        .testTarget(name: "MediaTests", dependencies: ["Media"])
```
and add `"Media"` to `NotchDeckApp`'s dependencies.

Run: `swift build` — expect a failure that `Sources/Media` has no sources yet; that is fine until Step 3.

- [ ] **Step 2: Write the failing test**

`Tests/MediaTests/NowPlayingDecoderTests.swift`:

```swift
import Testing
@testable import Media

@Suite("Now playing decoder")
struct NowPlayingDecoderTests {
    private let priming = #"{"type":"data","diff":false,"payload":{}}"#

    private let snapshot = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome",\
    "title":"Spike Test Track","artist":"NotchDeck Spike","album":"MediaRemote Probe",\
    "playing":true,"playbackRate":1,"elapsedTimeMicros":0,"durationMicros":125014014,\
    "timestampEpochMicros":1788357423000000,"contentItemIdentifier":"ABC"}}
    """

    @Test("the priming line yields no snapshot")
    func primingIsIgnored() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(line: priming) == nil)
    }

    @Test("a full payload becomes a snapshot")
    func fullSnapshot() throws {
        var decoder = NowPlayingDecoder()

        let state = try #require(decoder.consume(line: snapshot))

        #expect(state.bundleIdentifier == "com.google.Chrome")
        #expect(state.title == "Spike Test Track")
        #expect(state.artist == "NotchDeck Spike")
        #expect(state.isPlaying)
        #expect(state.playbackRate == 1)
        #expect(state.durationMicros == 125_014_014)
    }

    @Test("a diff changes only the keys it carries")
    func diffMerges() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let state = try #require(decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0}}"#
        ))

        #expect(!state.isPlaying)
        #expect(state.playbackRate == 0)
        #expect(state.title == "Spike Test Track")
        #expect(state.artist == "NotchDeck Spike")
    }

    @Test("an explicit null in a diff clears that field")
    func explicitNullClears() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let state = try #require(decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"artist":null}}"#
        ))

        #expect(state.artist == nil)
        #expect(state.album == "MediaRemote Probe")
    }

    @Test("a full payload replaces the state rather than merging into it")
    func fullPayloadReplaces() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let state = try #require(decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","title":"Other","playing":true}}"#
        ))

        #expect(state.title == "Other")
        #expect(state.artist == nil)
        #expect(state.album == nil)
    }

    @Test("a payload missing any required field yields no snapshot")
    func requiredFieldsAreRequired() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"title":"No bundle id","playing":true}}"#
        ) == nil)
    }

    @Test("a sparse payload with only the required fields still yields a snapshot")
    func sparsePayload() throws {
        var decoder = NowPlayingDecoder()

        let state = try #require(decoder.consume(
            line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"org.telegram","title":"Voice","playing":true}}"#
        ))

        #expect(state.artist == nil)
        #expect(state.album == nil)
        #expect(state.durationMicros == nil)
        #expect(state.playbackRate == 0)
    }

    @Test("artwork arriving in a later diff is attached to the existing track")
    func lateArtwork() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        let state = try #require(decoder.consume(
            line: #"{"type":"data","diff":true,"payload":{"artworkData":"QUJD","artworkMimeType":"image/jpeg"}}"#
        ))

        #expect(state.artwork?.data == Data("ABC".utf8))
        #expect(state.artwork?.mimeType == "image/jpeg")
    }

    @Test("a diff arriving before any snapshot is applied to an empty state")
    func diffBeforeSnapshot() {
        var decoder = NowPlayingDecoder()

        #expect(decoder.consume(line: #"{"type":"data","diff":true,"payload":{"playing":false}}"#) == nil)
    }

    @Test("a literal null document clears everything")
    func literalNullClears() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "null") == nil)
        #expect(decoder.snapshot == nil)
    }

    @Test("malformed input leaves the previous snapshot untouched")
    func malformedIsIgnored() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "{not json") == nil)
        #expect(decoder.snapshot?.title == "Spike Test Track")
    }

    @Test("a blank line is ignored")
    func blankLineIsIgnored() throws {
        var decoder = NowPlayingDecoder()
        _ = decoder.consume(line: snapshot)

        #expect(decoder.consume(line: "   ") == nil)
        #expect(decoder.snapshot != nil)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter NowPlayingDecoderTests`
Expected: FAIL — `cannot find 'NowPlayingDecoder' in scope`.

- [ ] **Step 4: Write the model**

`Sources/Media/NowPlaying.swift`:

```swift
import Foundation

/// A now-playing snapshot.
///
/// Only `bundleIdentifier`, `title` and `isPlaying` are dependable: the adapter's
/// key set varies by player, and browsers in particular omit most of the rest.
public struct NowPlaying: Equatable, Sendable {
    public struct Artwork: Equatable, Sendable {
        public var data: Data
        public var mimeType: String?
    }

    public var bundleIdentifier: String
    public var title: String
    public var isPlaying: Bool

    public var artist: String?
    public var album: String?
    public var contentItemIdentifier: String?
    public var artwork: Artwork?

    /// Zero while paused. Drives position interpolation — use this, not `isPlaying`.
    public var playbackRate: Double
    public var elapsedTimeMicros: Int64?
    public var durationMicros: Int64?
    /// When `elapsedTimeMicros` was measured, in epoch microseconds.
    public var timestampEpochMicros: Int64?
}
```

- [ ] **Step 5: Write the delta decoder**

`Sources/Media/PayloadDelta.swift`:

```swift
import Foundation

/// One field in a stream payload. The protocol distinguishes a key that was not
/// sent from one sent as an explicit null, and they mean different things:
/// absent leaves the value alone, null clears it.
public enum FieldUpdate<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case cleared
    case set(Value)

    /// Applies this update to an existing value.
    public func applied(to current: Value?) -> Value? {
        switch self {
        case .unchanged: current
        case .cleared: nil
        case .set(let value): value
        }
    }
}

/// The `payload` object of one stream line.
struct PayloadDelta: Decodable {
    var bundleIdentifier: FieldUpdate<String> = .unchanged
    var title: FieldUpdate<String> = .unchanged
    var artist: FieldUpdate<String> = .unchanged
    var album: FieldUpdate<String> = .unchanged
    var contentItemIdentifier: FieldUpdate<String> = .unchanged
    var playing: FieldUpdate<Bool> = .unchanged
    var playbackRate: FieldUpdate<Double> = .unchanged
    var elapsedTimeMicros: FieldUpdate<Int64> = .unchanged
    var durationMicros: FieldUpdate<Int64> = .unchanged
    var timestampEpochMicros: FieldUpdate<Int64> = .unchanged
    var artworkData: FieldUpdate<String> = .unchanged
    var artworkMimeType: FieldUpdate<String> = .unchanged

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, title, artist, album, contentItemIdentifier
        case playing, playbackRate, elapsedTimeMicros, durationMicros
        case timestampEpochMicros, artworkData, artworkMimeType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func update<T: Decodable & Equatable & Sendable>(_ key: CodingKeys) throws -> FieldUpdate<T> {
            guard container.contains(key) else { return .unchanged }
            if try container.decodeNil(forKey: key) { return .cleared }
            return .set(try container.decode(T.self, forKey: key))
        }

        bundleIdentifier = try update(.bundleIdentifier)
        title = try update(.title)
        artist = try update(.artist)
        album = try update(.album)
        contentItemIdentifier = try update(.contentItemIdentifier)
        playing = try update(.playing)
        playbackRate = try update(.playbackRate)
        elapsedTimeMicros = try update(.elapsedTimeMicros)
        durationMicros = try update(.durationMicros)
        timestampEpochMicros = try update(.timestampEpochMicros)
        artworkData = try update(.artworkData)
        artworkMimeType = try update(.artworkMimeType)
    }
}

struct StreamLine: Decodable {
    var diff: Bool
    var payload: PayloadDelta
}
```

- [ ] **Step 6: Write the decoder**

`Sources/Media/NowPlayingDecoder.swift`:

```swift
import Foundation

/// Merges the adapter's diff protocol into a running snapshot.
///
/// `diff:false` payloads replace the state outright; `diff:true` payloads merge,
/// with an explicit null clearing a field. A snapshot is produced only once the
/// three dependable fields are all known.
public struct NowPlayingDecoder {
    private struct Partial: Equatable {
        var bundleIdentifier: String?
        var title: String?
        var playing: Bool?
        var artist: String?
        var album: String?
        var contentItemIdentifier: String?
        var playbackRate: Double?
        var elapsedTimeMicros: Int64?
        var durationMicros: Int64?
        var timestampEpochMicros: Int64?
        var artworkBase64: String?
        var artworkMimeType: String?
    }

    private var partial = Partial()
    public private(set) var snapshot: NowPlaying?

    public init() {}

    /// Consumes one line of the stream. Returns the new snapshot when the line
    /// produced one, and nil when it did not — a priming line, a line that leaves
    /// the state incomplete, or unparseable input.
    @discardableResult
    public mutating func consume(line: String) -> NowPlaying? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "null" {
            partial = Partial()
            snapshot = nil
            return nil
        }

        guard let data = trimmed.data(using: .utf8),
              let line = try? JSONDecoder().decode(StreamLine.self, from: data) else {
            return nil
        }

        if !line.diff {
            partial = Partial()
        }
        apply(line.payload)
        snapshot = project()
        return snapshot
    }

    private mutating func apply(_ delta: PayloadDelta) {
        partial.bundleIdentifier = delta.bundleIdentifier.applied(to: partial.bundleIdentifier)
        partial.title = delta.title.applied(to: partial.title)
        partial.playing = delta.playing.applied(to: partial.playing)
        partial.artist = delta.artist.applied(to: partial.artist)
        partial.album = delta.album.applied(to: partial.album)
        partial.contentItemIdentifier = delta.contentItemIdentifier.applied(to: partial.contentItemIdentifier)
        partial.playbackRate = delta.playbackRate.applied(to: partial.playbackRate)
        partial.elapsedTimeMicros = delta.elapsedTimeMicros.applied(to: partial.elapsedTimeMicros)
        partial.durationMicros = delta.durationMicros.applied(to: partial.durationMicros)
        partial.timestampEpochMicros = delta.timestampEpochMicros.applied(to: partial.timestampEpochMicros)
        partial.artworkBase64 = delta.artworkData.applied(to: partial.artworkBase64)
        partial.artworkMimeType = delta.artworkMimeType.applied(to: partial.artworkMimeType)
    }

    private func project() -> NowPlaying? {
        guard let bundleIdentifier = partial.bundleIdentifier,
              let title = partial.title,
              let playing = partial.playing else {
            return nil
        }

        var artwork: NowPlaying.Artwork?
        if let base64 = partial.artworkBase64, let data = Data(base64Encoded: base64) {
            artwork = NowPlaying.Artwork(data: data, mimeType: partial.artworkMimeType)
        }

        return NowPlaying(
            bundleIdentifier: bundleIdentifier,
            title: title,
            isPlaying: playing,
            artist: partial.artist,
            album: partial.album,
            contentItemIdentifier: partial.contentItemIdentifier,
            artwork: artwork,
            playbackRate: partial.playbackRate ?? 0,
            elapsedTimeMicros: partial.elapsedTimeMicros,
            durationMicros: partial.durationMicros,
            timestampEpochMicros: partial.timestampEpochMicros
        )
    }
}
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter NowPlayingDecoderTests`
Expected: 12 tests pass. Full suite still green.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/Media Tests/MediaTests
git commit -m "feat: decode the media adapter's now-playing stream"
```

---

## Task 6: Playback position interpolation

**Files:**
- Create: `Sources/Media/PlaybackPosition.swift`
- Test: `Tests/MediaTests/PlaybackPositionTests.swift`

The adapter's position never ticks: it is the position as of `timestampEpochMicros`. Worse, the spike found that on resume the framework restamps the timestamp **without** resending the elapsed value, so an implementation that trusts `isPlaying` and ignores `playbackRate` reports a position that jumps backwards.

- [ ] **Step 1: Write the failing test**

`Tests/MediaTests/PlaybackPositionTests.swift`:

```swift
import Testing
@testable import Media

@Suite("Playback position")
struct PlaybackPositionTests {
    private let start: Int64 = 1_788_357_423_000_000

    private func track(
        rate: Double,
        elapsed: Int64?,
        timestamp: Int64?,
        duration: Int64? = 125_000_000
    ) -> NowPlaying {
        NowPlaying(
            bundleIdentifier: "com.example",
            title: "Track",
            isPlaying: rate > 0,
            playbackRate: rate,
            elapsedTimeMicros: elapsed,
            durationMicros: duration,
            timestampEpochMicros: timestamp
        )
    }

    @Test("a playing track advances in real time")
    func playingAdvances() {
        let state = track(rate: 1, elapsed: 10_000_000, timestamp: start)

        let position = PlaybackPosition.micros(of: state, atEpochMicros: start + 5_000_000)

        #expect(position == 15_000_000)
    }

    @Test("a paused track does not advance, however long ago it was measured")
    func pausedIsFrozen() {
        let state = track(rate: 0, elapsed: 10_000_000, timestamp: start)

        let position = PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000)

        #expect(position == 10_000_000)
    }

    @Test("a restamped timestamp with no new elapsed value does not rewind the track")
    func restampedTimestampDoesNotRewind() {
        // On resume the adapter sends a fresh timestamp and playbackRate but keeps
        // the elapsed value from the pause. Interpolating from the new timestamp is
        // correct; interpolating from the old one would jump forward by the pause.
        let paused = track(rate: 0, elapsed: 28_000_000, timestamp: start)
        let resumed = track(rate: 1, elapsed: 28_000_000, timestamp: start + 6_000_000)

        #expect(PlaybackPosition.micros(of: paused, atEpochMicros: start + 6_000_000) == 28_000_000)
        #expect(PlaybackPosition.micros(of: resumed, atEpochMicros: start + 6_000_000) == 28_000_000)
        #expect(PlaybackPosition.micros(of: resumed, atEpochMicros: start + 8_000_000) == 30_000_000)
    }

    @Test("a double-speed track advances twice as fast")
    func rateIsHonoured() {
        let state = track(rate: 2, elapsed: 0, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 5_000_000) == 10_000_000)
    }

    @Test("position is clamped to the duration")
    func clampedToDuration() {
        let state = track(rate: 1, elapsed: 124_000_000, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000) == 125_000_000)
    }

    @Test("position never goes negative when the clock runs backwards")
    func neverNegative() {
        let state = track(rate: 1, elapsed: 1_000_000, timestamp: start)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start - 60_000_000) == 0)
    }

    @Test("an unknown duration leaves the position unclamped")
    func unknownDuration() {
        let state = track(rate: 1, elapsed: 0, timestamp: start, duration: nil)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 900_000_000) == 900_000_000)
    }

    @Test("a track with no elapsed value has no position")
    func missingElapsed() {
        #expect(PlaybackPosition.micros(of: track(rate: 1, elapsed: nil, timestamp: start), atEpochMicros: start) == nil)
    }

    @Test("a track with no timestamp reports its elapsed value unchanged")
    func missingTimestamp() {
        let state = track(rate: 1, elapsed: 7_000_000, timestamp: nil)

        #expect(PlaybackPosition.micros(of: state, atEpochMicros: start + 60_000_000) == 7_000_000)
    }

    @Test("progress is the fraction of the duration, and nil without one")
    func progress() {
        let state = track(rate: 0, elapsed: 25_000_000, timestamp: start)

        #expect(PlaybackPosition.progress(of: state, atEpochMicros: start) == 0.2)
        #expect(PlaybackPosition.progress(of: track(rate: 0, elapsed: 1, timestamp: start, duration: nil), atEpochMicros: start) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PlaybackPositionTests`
Expected: FAIL — `cannot find 'PlaybackPosition' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/Media/PlaybackPosition.swift`:

```swift
import Foundation

/// Works out where a track actually is right now.
///
/// The adapter reports a position measured at a timestamp and never updates it
/// again until something changes, so the current position has to be interpolated.
/// `playbackRate` — not `isPlaying` — is what drives it: the adapter restamps the
/// timestamp on resume without resending the elapsed value, and a rate of zero is
/// what keeps a paused track from drifting.
public enum PlaybackPosition {
    public static func micros(of state: NowPlaying, atEpochMicros now: Int64) -> Int64? {
        guard let elapsed = state.elapsedTimeMicros else { return nil }
        guard let timestamp = state.timestampEpochMicros else { return elapsed }

        let drift = Double(now - timestamp) * state.playbackRate
        var position = elapsed + Int64(drift)

        if let duration = state.durationMicros {
            position = min(position, duration)
        }
        return max(position, 0)
    }

    public static func progress(of state: NowPlaying, atEpochMicros now: Int64) -> Double? {
        guard let duration = state.durationMicros, duration > 0,
              let position = micros(of: state, atEpochMicros: now) else {
            return nil
        }
        return Double(position) / Double(duration)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter PlaybackPositionTests`
Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Media/PlaybackPosition.swift Tests/MediaTests/PlaybackPositionTests.swift
git commit -m "feat: interpolate playback position between adapter updates"
```

---

## Task 7: Transport commands

**Files:**
- Create: `Sources/Media/MediaCommands.swift`
- Test: `Tests/MediaTests/MediaCommandsTests.swift`

The adapter sends commands as one-shot processes: `send <id>` with 0 play, 1 pause, 2 toggle, 4 next, 5 previous, and `seek <microseconds>`. When the adapter is unavailable — the `test` probe failed, or a command exits non-zero — transport falls back to system media keys, which work with any player.

Seek has no fallback: there is no media key for it. A failed seek reports failure so the UI can put the scrubber back.

- [ ] **Step 1: Write the failing test**

`Tests/MediaTests/MediaCommandsTests.swift`:

```swift
import Testing
@testable import Media

final class RecordingRunner: AdapterCommandRunner, @unchecked Sendable {
    var invocations: [[String]] = []
    var result = true

    func run(arguments: [String]) async -> Bool {
        invocations.append(arguments)
        return result
    }
}

final class RecordingKeyPoster: MediaKeyPoster, @unchecked Sendable {
    var posted: [Int32] = []

    func post(keyCode: Int32) {
        posted.append(keyCode)
    }
}

@Suite("Media commands")
struct MediaCommandsTests {
    @Test("each transport action maps to the adapter's command id")
    func adapterCommandIDs() async {
        let runner = RecordingRunner()
        let commands = MediaCommands(adapter: runner, keys: RecordingKeyPoster())

        for action in [TransportAction.play, .pause, .toggle, .next, .previous] {
            await commands.perform(action)
        }

        #expect(runner.invocations == [
            ["send", "0"], ["send", "1"], ["send", "2"], ["send", "4"], ["send", "5"]
        ])
    }

    @Test("a successful adapter command does not also post a media key")
    func noDoubleDispatch() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: RecordingRunner(), keys: keys)

        await commands.perform(.next)

        #expect(keys.posted.isEmpty)
    }

    @Test("a failing adapter command falls back to the media key")
    func fallsBackOnFailure() async {
        let runner = RecordingRunner()
        runner.result = false
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: runner, keys: keys)

        await commands.perform(.next)

        #expect(keys.posted == [TransportAction.next.mediaKeyCode])
    }

    @Test("with no adapter at all, every action goes straight to a media key")
    func noAdapterUsesKeys() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: nil, keys: keys)

        await commands.perform(.play)
        await commands.perform(.previous)

        #expect(keys.posted == [16, 18])
    }

    @Test("play, pause and toggle all use the play media key")
    func transportKeysCollapse() {
        #expect(TransportAction.play.mediaKeyCode == 16)
        #expect(TransportAction.pause.mediaKeyCode == 16)
        #expect(TransportAction.toggle.mediaKeyCode == 16)
        #expect(TransportAction.next.mediaKeyCode == 17)
        #expect(TransportAction.previous.mediaKeyCode == 18)
    }

    @Test("seek passes microseconds to the adapter")
    func seekUsesMicroseconds() async {
        let runner = RecordingRunner()
        let commands = MediaCommands(adapter: runner, keys: RecordingKeyPoster())

        let succeeded = await commands.seek(toMicros: 60_000_000)

        #expect(succeeded)
        #expect(runner.invocations == [["seek", "60000000"]])
    }

    @Test("seek reports failure rather than falling back, because no media key can seek")
    func seekHasNoFallback() async {
        let keys = RecordingKeyPoster()
        let commands = MediaCommands(adapter: nil, keys: keys)

        let succeeded = await commands.seek(toMicros: 1_000)

        #expect(!succeeded)
        #expect(keys.posted.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MediaCommandsTests`
Expected: FAIL — `cannot find 'MediaCommands' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/Media/MediaCommands.swift`:

```swift
import AppKit

public enum TransportAction: Equatable, Sendable {
    case play, pause, toggle, next, previous

    /// The adapter's `send` command id.
    var adapterCommandID: Int {
        switch self {
        case .play: 0
        case .pause: 1
        case .toggle: 2
        case .next: 4
        case .previous: 5
        }
    }

    /// The `NX_KEYTYPE_*` code for the fallback. Play, pause and toggle all share
    /// the play key, which is itself a toggle.
    var mediaKeyCode: Int32 {
        switch self {
        case .play, .pause, .toggle: 16
        case .next: 17
        case .previous: 18
        }
    }
}

/// Runs a one-shot adapter command, reporting whether it exited cleanly.
public protocol AdapterCommandRunner: Sendable {
    func run(arguments: [String]) async -> Bool
}

/// Posts a system-defined media key event.
public protocol MediaKeyPoster: Sendable {
    func post(keyCode: Int32)
}

public struct MediaCommands: Sendable {
    private let adapter: (any AdapterCommandRunner)?
    private let keys: any MediaKeyPoster

    public init(adapter: (any AdapterCommandRunner)?, keys: any MediaKeyPoster) {
        self.adapter = adapter
        self.keys = keys
    }

    public func perform(_ action: TransportAction) async {
        if let adapter, await adapter.run(arguments: ["send", String(action.adapterCommandID)]) {
            return
        }
        keys.post(keyCode: action.mediaKeyCode)
    }

    /// Seeking has no media-key equivalent, so a missing or failing adapter is
    /// simply a failure the caller has to show.
    public func seek(toMicros micros: Int64) async -> Bool {
        guard let adapter else { return false }
        return await adapter.run(arguments: ["seek", String(micros)])
    }
}

/// Posts `NX_KEYTYPE_*` events through the HID event tap.
///
/// Note: synthesising input may require Accessibility permission on macOS 26. This
/// is only the fallback path — the adapter needs no permission at all — so a
/// failure here degrades transport rather than breaking the module. Verify the
/// behaviour by hand and record the result in the README checklist.
public struct SystemMediaKeyPoster: MediaKeyPoster {
    public init() {}

    public func post(keyCode: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((keyCode << 16)) | Int(isDown ? 0xA00 : 0xB00),
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter MediaCommandsTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Media/MediaCommands.swift Tests/MediaTests/MediaCommandsTests.swift
git commit -m "feat: send transport commands with a media-key fallback"
```

---

## Task 8: The adapter subprocess

**Files:**
- Create: `Sources/Media/MediaAdapterProcess.swift`
- Test: `Tests/MediaTests/AdapterBackoffTests.swift`

The `stream` command is a long-lived subprocess emitting NDJSON. It emits **nothing at all** when nothing changes — no heartbeat — so silence is normal and must never be treated as a fault. What must be handled is the process exiting: the supervisor restarts it with a backoff.

Paths must be absolute, and the framework directory name must match the binary inside it.

- [ ] **Step 1: Write the failing test**

`Tests/MediaTests/AdapterBackoffTests.swift`:

```swift
import Testing
@testable import Media

@Suite("Adapter restart backoff")
struct AdapterBackoffTests {
    @Test("the first restart is immediate so a one-off crash is invisible")
    func firstRestartIsImmediate() {
        #expect(AdapterBackoff.delay(forAttempt: 0) == .zero)
    }

    @Test("the delay grows with consecutive failures")
    func delayGrows() {
        let first = AdapterBackoff.delay(forAttempt: 1)
        let second = AdapterBackoff.delay(forAttempt: 2)
        let third = AdapterBackoff.delay(forAttempt: 3)

        #expect(first < second)
        #expect(second < third)
    }

    @Test("the delay is capped so the module always recovers eventually")
    func delayIsCapped() {
        #expect(AdapterBackoff.delay(forAttempt: 50) == AdapterBackoff.maximumDelay)
        #expect(AdapterBackoff.delay(forAttempt: 5000) == AdapterBackoff.maximumDelay)
    }

    @Test("a negative attempt count is treated as the first attempt")
    func negativeAttemptIsSafe() {
        #expect(AdapterBackoff.delay(forAttempt: -3) == .zero)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AdapterBackoffTests`
Expected: FAIL — `cannot find 'AdapterBackoff' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/Media/MediaAdapterProcess.swift`:

```swift
import Foundation
import Support

/// Absolute paths to the vendored adapter inside the app bundle. The perl script
/// derives the dylib name from the framework directory's basename, so neither can
/// be renamed independently, and both paths must be absolute — a relative one
/// passes the existence check and then fails at load.
public struct AdapterPaths: Sendable {
    public let script: URL
    public let framework: URL

    public init(script: URL, framework: URL) {
        self.script = script
        self.framework = framework
    }

    public static func inMainBundle(_ bundle: Bundle = .main) -> AdapterPaths? {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL else {
            return nil
        }
        let framework = frameworks.appending(path: "MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework.path(percentEncoded: false)) else {
            return nil
        }
        return AdapterPaths(script: script, framework: framework)
    }

    func arguments(_ command: [String]) -> [String] {
        [script.path(percentEncoded: false), framework.path(percentEncoded: false)] + command
    }
}

public enum AdapterBackoff {
    public static let maximumDelay: Duration = .seconds(30)

    /// The first restart is immediate, so a single crash is invisible to the user;
    /// after that the delay doubles up to the cap.
    public static func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return .zero }
        let seconds = min(pow(2.0, Double(attempt - 1)), 30)
        return min(.seconds(seconds), maximumDelay)
    }
}

/// A source of NDJSON lines from the adapter's `stream` command.
public protocol AdapterStreamSource: Sendable {
    /// Lines until the underlying process exits. Long silences are normal.
    func lines() -> AsyncStream<String>
    func stop()
}

/// Spawns `/usr/bin/perl` on the vendored adapter and yields one line per JSON
/// object. `--micros` gives integer epoch microseconds instead of an ISO date, and
/// `--debounce` coalesces the two-line bursts a single state change produces.
public final class PerlAdapterStream: AdapterStreamSource, @unchecked Sendable {
    private let paths: AdapterPaths
    private let logger = Log.make("media.adapter")
    private let lock = NSLock()
    private var process: Process?

    public init(paths: AdapterPaths) {
        self.paths = paths
    }

    public func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = paths.arguments(["stream", "--micros", "--debounce=50"])

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            var buffer = Data()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let text = String(data: line, encoding: .utf8) {
                        continuation.yield(text)
                    }
                }
            }

            process.terminationHandler = { [weak self] finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.logger.notice("adapter stream exited with status \(finished.terminationStatus, privacy: .public)")
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }

            do {
                try process.run()
                lock.withLock { self.process = process }
            } catch {
                logger.error("could not start the adapter: \(error.localizedDescription, privacy: .public)")
                continuation.finish()
            }
        }
    }

    public func stop() {
        let running = lock.withLock { () -> Process? in
            defer { process = nil }
            return process
        }
        running?.terminate()
    }
}

/// Runs one-shot adapter commands.
public struct PerlAdapterCommandRunner: AdapterCommandRunner {
    private let paths: AdapterPaths

    public init(paths: AdapterPaths) {
        self.paths = paths
    }

    public func run(arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = paths.arguments(arguments)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Runs the adapter's `test` command, which exits 0 when MediaRemote access
    /// genuinely works. Used once at launch to decide whether to degrade.
    public func probe() async -> Bool {
        await run(arguments: ["test"])
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter AdapterBackoffTests`
Expected: 4 tests pass. Full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Media/MediaAdapterProcess.swift Tests/MediaTests/AdapterBackoffTests.swift
git commit -m "feat: supervise the adapter streaming subprocess"
```

---

## Task 9: The media module and expanded player

**Files:**
- Create: `Sources/Media/MediaModule.swift`
- Create: `Sources/Media/MediaPlayerView.swift`

- [ ] **Step 1: Write the module**

`Sources/Media/MediaModule.swift`:

```swift
import AppKit
import NotchCore
import NotchUI
import Observation
import SwiftUI
import Support

@MainActor
@Observable
public final class MediaModule: NotchModule {
    public static let id = ModuleID("media")
    public let title = "Media"
    public let symbolName = "play.circle"

    /// The current track, or nil when nothing is known.
    public private(set) var state: NowPlaying?
    /// True once the adapter probe has failed; the UI explains itself instead of
    /// pretending nothing is playing.
    public private(set) var isDegraded = false
    /// Ticks once a second while a track is playing so the scrubber advances.
    public private(set) var positionTick: Int64 = 0
    /// Set while the user drags the scrubber, so incoming updates do not fight them.
    public var scrubbingProgress: Double?

    private let logger = Log.make("media")
    private let paths: AdapterPaths?
    private let commands: MediaCommands
    private var decoder = NowPlayingDecoder()
    private var streamTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// A paused track older than this stops appearing in the collapsed notch. The
    /// adapter never says "stopped", so this is our own policy.
    private let peekStaleness: Duration = .seconds(90)

    public init(paths: AdapterPaths? = AdapterPaths.inMainBundle()) {
        self.paths = paths
        let runner = paths.map(PerlAdapterCommandRunner.init(paths:))
        self.commands = MediaCommands(adapter: runner, keys: SystemMediaKeyPoster())
    }

    // MARK: NotchModule

    public func activate() {
        // Both halves are independently idempotent: the stream starts once and
        // outlives the panel, while the tick is panel-scoped and restarts every
        // time the notch opens.
        if streamTask == nil {
            startStream()
        }
        if tickTask == nil {
            startTicking()
        }
    }

    public func deactivate() {
        // The stream is the module's live state, not the panel's: it must keep
        // running while the notch is closed, or the peek would have nothing to
        // show. Only the once-a-second UI tick is panel-scoped.
        tickTask?.cancel()
        tickTask = nil
    }

    public func expandedView() -> AnyView {
        AnyView(MediaPlayerView(module: self))
    }

    public func peekView() -> AnyView? {
        guard let state, isFresh(state) else { return nil }
        return AnyView(MediaPeekView(state: state))
    }

    // MARK: Playback

    public func perform(_ action: TransportAction) {
        Task { await commands.perform(action) }
    }

    public func seek(toProgress progress: Double) {
        guard let duration = state?.durationMicros else { return }
        let target = Int64(Double(duration) * min(max(progress, 0), 1))
        Task {
            let succeeded = await commands.seek(toMicros: target)
            if !succeeded {
                logger.notice("seek failed; the adapter is unavailable")
            }
            scrubbingProgress = nil
        }
    }

    public var progress: Double? {
        if let scrubbingProgress { return scrubbingProgress }
        guard let state else { return nil }
        return PlaybackPosition.progress(of: state, atEpochMicros: Self.nowMicros())
    }

    public var positionMicros: Int64? {
        guard let state else { return nil }
        return PlaybackPosition.micros(of: state, atEpochMicros: Self.nowMicros())
    }

    // MARK: Internals

    static func nowMicros() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000_000)
    }

    private func isFresh(_ state: NowPlaying) -> Bool {
        guard state.playbackRate == 0 else { return true }
        guard let timestamp = state.timestampEpochMicros else { return false }
        let age = Self.nowMicros() - timestamp
        return age < Int64(peekStaleness.components.seconds) * 1_000_000
    }

    private func startStream() {
        guard let paths else {
            isDegraded = true
            logger.error("the media adapter is missing from the bundle")
            return
        }

        streamTask = Task { [weak self] in
            let runner = PerlAdapterCommandRunner(paths: paths)
            let works = await runner.probe()
            guard let self else { return }
            if !works {
                self.isDegraded = true
                self.logger.error("the media adapter probe failed; transport only")
                return
            }

            var attempt = 0
            while !Task.isCancelled {
                let delay = AdapterBackoff.delay(forAttempt: attempt)
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                let source = PerlAdapterStream(paths: paths)
                var sawAnything = false
                for await line in source.lines() {
                    sawAnything = true
                    self.consume(line)
                }
                attempt = sawAnything ? 0 : attempt + 1
            }
        }
    }

    private func consume(_ line: String) {
        if let updated = decoder.consume(line: line) {
            state = updated
        } else if decoder.snapshot == nil {
            state = nil
        }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.positionTick &+= 1
            }
        }
    }
}
```

- [ ] **Step 2: Write the player view**

`Sources/Media/MediaPlayerView.swift`:

```swift
import SwiftUI

struct MediaPlayerView: View {
    @Bindable var module: MediaModule

    var body: some View {
        if module.isDegraded && module.state == nil {
            unavailable
        } else if let state = module.state {
            player(state)
        } else {
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            Text("Now playing is unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text("Playback controls still work.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            transport
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func player(_ state: NowPlaying) -> some View {
        HStack(spacing: 14) {
            artwork(state)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist ?? state.album ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                scrubber

                transport
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func artwork(_ state: NowPlaying) -> some View {
        if let data = state.artwork?.data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.3)))
        }
    }

    @ViewBuilder
    private var scrubber: some View {
        if let progress = module.progress {
            // `positionTick` is read so the once-a-second tick redraws the bar.
            let _ = module.positionTick
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            module.scrubbingProgress = min(max(value.location.x / proxy.size.width, 0), 1)
                        }
                        .onEnded { value in
                            module.seek(toProgress: min(max(value.location.x / proxy.size.width, 0), 1))
                        }
                )
            }
            .frame(height: 4)
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            button("backward.fill") { module.perform(.previous) }
            button(module.state?.isPlaying == true ? "pause.fill" : "play.fill") { module.perform(.toggle) }
            button("forward.fill") { module.perform(.next) }
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds, zero warnings.

- [ ] **Step 4: Commit**

```bash
git add Sources/Media/MediaModule.swift Sources/Media/MediaPlayerView.swift
git commit -m "feat: add the media module and expanded player"
```

---

## Task 10: The collapsed peek

**Files:**
- Create: `Sources/Media/MediaPeekView.swift`

The peek fills the widened collapsed notch: artwork on one side of the camera housing, a level indicator on the other. It appears only while a track is fresh, per the module's staleness policy.

- [ ] **Step 1: Write the view**

`Sources/Media/MediaPeekView.swift`:

```swift
import SwiftUI

struct MediaPeekView: View {
    let state: NowPlaying

    var body: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Spacer(minLength: 0)
            Visualiser(isAnimating: state.isPlaying)
                .frame(width: 18, height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = state.artwork?.data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.15))
        }
    }
}

/// Three bars that breathe while a track plays and rest flat when it is paused.
private struct Visualiser: View {
    let isAnimating: Bool
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 3, height: height(index))
            }
        }
        .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = isAnimating ? 1 : 0 }
        .onChange(of: isAnimating) { _, playing in phase = playing ? 1 : 0 }
    }

    private func height(_ index: Int) -> CGFloat {
        guard phase > 0 else { return 3 }
        return [10.0, 6.0, 12.0][index]
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build
git add Sources/Media/MediaPeekView.swift
git commit -m "feat: show now playing in the collapsed notch"
```

---

## Task 11: Horizontal swipe changes track

**Files:**
- Modify: `Sources/NotchWindow/NotchEventMonitor.swift`

P0's accumulator already classifies horizontal swipes into `.left` and `.right`, and the notch reducer deliberately ignores them — changing tracks is not notch state. The monitor gains a second callback so the app can route them to the media module.

- [ ] **Step 1: Add the callback**

In `NotchEventMonitor`, add a stored `private let onHorizontalSwipe: (ScrollDirection) -> Void` taken in `init` after `send`. In `handleScroll`, replace the switch that discards horizontal directions:

```swift
        switch gesture {
        case .down, .up:
            send(.scrolled(gesture))
        case .left, .right:
            // Track changes are the media module's business; the notch state
            // machine has nothing to say about them.
            onHorizontalSwipe(gesture)
        }
```

Keep the pointer reconciliation at the top of `handleScroll` unchanged — it is what guarantees the reducer knows the pointer is over the notch before any scroll-driven transition.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: fails in `AppDelegate`, which does not yet pass the new argument. Task 12 fixes it.

- [ ] **Step 3: Commit with Task 12**

This task and the next form one commit, because the branch does not build in between.

---

## Task 12: Wire the app together

**Files:**
- Modify: `Sources/NotchDeckApp/AppDelegate.swift`
- Modify: `Sources/NotchWindow/NotchSurface.swift`, `Sources/NotchWindow/NotchSurfaceManager.swift`
- Modify: `README.md`

- [ ] **Step 1: Thread the registry through to surfaces**

`NotchViewModel` now takes a `ModuleRegistry`. `NotchSurface.init` and `NotchSurfaceManager.init` must accept one and pass it down. Give `NotchSurfaceManager.init` a `registry: ModuleRegistry` parameter before `syntheticSize`.

- [ ] **Step 2: Build the object graph in the delegate**

In `applicationDidFinishLaunching`, before the surface manager:

```swift
        let registry = ModuleRegistry()
        let media = MediaModule()
        registry.register(media)
        self.registry = registry
        self.media = media
```

Pass `registry` into `NotchSurfaceManager`. Extend the state-change handler so the registry learns when the panel is visible, which is what starts and stops panel-scoped work:

```swift
        controller.onStateChange = { state in
            surfaces.apply(mode: state.mode)
            registry.setPanelVisible(state.isExpanded)
        }
```

Give the monitor the swipe route:

```swift
        let monitor = NotchEventMonitor(
            surfaces: surfaces,
            send: { [weak self] event in self?.controller.send(event) },
            onHorizontalSwipe: { [weak media] direction in
                media?.perform(direction == .left ? .next : .previous)
            }
        )
```

A leftward swipe moves forward, matching the natural-scrolling convention the accumulator documents.

Finally, start the media stream at launch so the peek works before the panel is ever opened:

```swift
        media.activate()
```

Add `registry` and `media` as strong stored properties on the delegate.

- [ ] **Step 3: Build and run**

```bash
swift build
swift test
./Scripts/run.sh
```
Expected: warning-free build, all tests green, the app launches.

- [ ] **Step 4: Update the README**

Add to the manual verification checklist:

- [ ] With music playing in any app — Music, Spotify, a browser tab — the collapsed notch shows its artwork and an animated indicator.
- [ ] Opening the notch shows the track's artwork, title and artist, a scrubber that advances once a second, and working previous / play-pause / next.
- [ ] Dragging the scrubber seeks the track on release.
- [ ] Pausing in the source app is reflected within a second, and the visualiser rests.
- [ ] A two-finger horizontal swipe over the notch changes track.
- [ ] Stopping playback entirely makes the peek disappear after the staleness window, without the panel losing the track.
- [ ] With nothing ever played since login, the panel says "Nothing playing" rather than showing a stale track.
- [ ] Quitting and relaunching leaves no orphaned `perl` process: `pgrep -f mediaremote-adapter` is empty.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchDeckApp Sources/NotchWindow README.md
git commit -m "feat: wire the media module into the app"
```

---

## Verification beyond the checklist

Two things the checklist cannot express and a human must confirm once:

- **No orphaned subprocesses.** The stream is a long-lived `perl` process. Quit NotchDeck and confirm `pgrep -f mediaremote-adapter` is empty. Kill NotchDeck with `SIGKILL` and confirm the same — `continuation.onTermination` will not run, so if a process survives, the supervisor needs a `Process.terminate` on a parent-death path.
- **The media-key fallback.** Rename the framework inside a built bundle so the probe fails, relaunch, and confirm the transport buttons still control playback. If they do not, synthesising media keys needs Accessibility permission on macOS 26 and the README must say so.

## Out of scope for P1a

- The file shelf, drag and drop, and AirDrop — P1b, which begins with a spike proving a file can be dropped onto a non-activating panel
- Reordering or disabling modules in a settings UI — P4. `ModuleLayout` supports both; nothing exposes them yet
- Persisting the layout across launches — P4, alongside the rest of the preferences store
- Per-screen module selection — the registry is deliberately shared, matching P0's single shared mode
