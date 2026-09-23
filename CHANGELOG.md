# Changelog

All notable changes to NotchDeck. Versions follow [Semantic Versioning](https://semver.org).
Full notes for each version are on the [releases page](https://github.com/skensell201/notchdeck/releases).

## [0.3.2] — 2026-09-23

### Changed
- New app icon: the notch at the top of a screen, with a fanned deck of module
  cards dropping out of it. It is drawn as an SVG (`Resources/AppIcon.svg`) and
  rendered by `Scripts/make-icon.sh`, which replaces the Pillow-based
  `make-icon.py`.
- Documentation reorganised: a user-facing README, plus
  [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), [`docs/TESTING.md`](docs/TESTING.md),
  this changelog and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Design specs
  and plans moved to `docs/specs/` and `docs/plans/`.

## [0.3.1] — 2026-09-15

### Changed
- The collapsed notch keeps its own width while music plays or a timer runs. The
  wide band is now opt-in: **Settings → Notch → Widen the notch for what is playing**.
- The volume-overlay switch is now called **Hide the system volume overlay**, which
  is what it does.

## [0.3.0] — 2026-09-15

### Added
- Devices announce themselves as a drop: the notch sags, and a capsule carrying the
  device's name falls out of it. An announcement arriving while the panel is open
  falls out of the panel and leaves it open.
- The expanded panel can be tinted (Settings → Notch). The part over the camera
  housing stays black.
- Settings → Notch lists the attached displays and marks which have a real notch.

### Changed
- One source for audio devices: connecting headphones announces once, not twice,
  and headphones put back on are announced even though they never left the list.

### Removed
- The volume announcement — macOS already draws one.

## [0.2.0] — 2026-09-07

### Added
- The app has an icon.

### Fixed
- The Mirror tab showed nothing: the preview layer was sized before layout. The
  mirror flip now goes through the capture connection.

## [0.1.0] — 2026-09-03

First release: the notch surface on the built-in display and a synthetic one on
external displays, with Media, Shelf, Clipboard, Timer, Stats, Mirror, Shortcuts
and Calendar modules, live activities, optional volume-overlay suppression, and a
settings window.

[0.3.2]: https://github.com/skensell201/notchdeck/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/skensell201/notchdeck/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/skensell201/notchdeck/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/skensell201/notchdeck/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/skensell201/notchdeck/releases/tag/v0.1.0
