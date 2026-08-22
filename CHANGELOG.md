# Changelog

All notable changes to **The Keyboard Project** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed
- **The shipping keyboard no longer runs the M0 diagnostics harness.** It was never gated out
  of Release: every keyboard appearance, in every app, did a UUID file write + read-back +
  delete in the App Group container, a pasteboard IPC probe, a JSON encode and a second
  verified write — plus a 1 Hz timer for as long as the keyboard was on screen.
  `DiagnosticsRunner` and `DiagnosticsPanel` now compile out of Release entirely (verified:
  zero matching symbols in the shipped `.appex`) and remain fully available in Debug.
- **Host app is a setup screen, not a dashboard.** The three-step checklist leads, with a
  button into this app's Settings page; the M0 verdicts, keyboard report and memory readings
  moved to a Debug-only Developer section. After setup the keyboard is reached from the globe
  key and the app never needs opening again.
- The keyboard's strip no longer shows the `"M1"` label or a memory readout in Release. Its
  height is kept as reserved space for M4's suggestion bar, so Debug and Release keyboards
  stay the same shape.

### Added
- `KeyboardHandshake` — the one record the extension writes to the App Group in a shipping
  build (that it ran, and whether Full Access is on, which only the extension can see).
  Throttled and written off the main thread.
- Signing-expiry countdown in the host app, so the free personal team's 7-day lapse is visible
  before the keyboard stops working, plus `Scripts/redeploy.sh` to renew it in one command.
- In-app privacy statement (nothing leaves the device, no network code at all).
- `scrollUntilHittable` in the UI-test harness, so onboarding copy changes cannot masquerade
  as touch-layer failures.

### Fixed
- The keyboard's memory readout never updated. `diagnostics` is a nested `ObservableObject`
  and does not forward `objectWillChange`, so the 1 Hz timer mutated a value nothing observed.
  The Debug strip now observes the runner directly.
- Duplicate constraint IDs in `docs/CONSTRAINTS.md`: `C-31` and `C-32` each named two
  different facts, which breaks the citation scheme the project's methodology depends on. The
  build-configuration pair was renumbered to `C-56`/`C-57`; the widely-cited Privacy Manifest
  pair kept its numbers.

### Removed
- `AppLogo.imageset` — a 1024×1024, ~990 KB image referenced by nothing in the tree. Roughly
  halves `Assets.car`.

## [0.1.0] - 2026-08-21

### Added
- **Official App Icon & Identity:** Minimalist geometric "3-Row Horizon" icon and asset catalog.
- **Host App (`KeyboardProject`):**
  - Interactive M0 feasibility test harness and live status dashboard.
  - In-app keyboard preview view for side-by-side layout verification.
  - Setup guide with live permission diagnostics (Full Access, Pasteboard permission).
  - App Groups shared container round-trip verification.
- **Keyboard Extension (`KeyboardExtension`):**
  - Base QWERTY layout grid with Android Gboard key-width percentage geometry.
  - Function row matching Gboard (symbols, comma, spacebar, period, return).
  - Multi-layer support (Base lowercase, Shifted uppercase, Caps lock, Symbols `?123`, Extended `=\<`).
  - Haptic feedback and native click sound integrations.
  - Diagnostics panel accessible directly from the keyboard extension bar.
- **Project & Tooling:**
  - Complete XcodeGen configuration (`project.yml`) supporting reproducible builds without tracking `.xcodeproj`.
  - Comprehensive unit test suite (`KeyboardProjectTests`) verifying layout math and typing behavior.
  - Continuous integration workflows via GitHub Actions.
  - Full documentation suite: Architecture, Constraints, Clipboard specification, UI specification, and ADR decision log.
