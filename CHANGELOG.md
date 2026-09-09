# Changelog

Notable changes to The Keyboard Project are recorded here. The project follows semantic
versioning after its first public release.

## Unreleased

### Added

- Manual, consented tap-to-save clipboard history in the host app and keyboard panel.
- Pin/unpin, delete, confirmed clear-all, one-hour recent expiry and shortened-item labels.
- Versioned asynchronous clipboard repository with typed failures, atomic protected writes,
  backup exclusion, recovery fencing, migrations and cross-context stale-result protection.
- Persistent haptic, sound, System/Light/Black/Neon theme and clipboard preferences.
- Token-driven key gradients, borders, pressed states, monoline function icons and a ViewMax
  design handoff under `assets/themes/`.
- VoiceOver key activation and accessible clipboard/settings actions.
- Deterministic clipboard fixtures, expanded typing/storage regression suites, static privacy
  checks and a release-evidence gate.
- Physical-device deploy workflow that verifies signing, profiles and App Group entitlements,
  installs with `devicectl`, confirms installation and launches the host app.

### Changed

- v1 is now explicitly iPhone-first, English (US), offline and dependency-free.
- Clipboard access is manual-first. Opening or foregrounding either target never reads a
  clipboard value; automatic capture is unavailable.
- Clipboard limits are 50 recent, 25 pinned, one hour, 16 KiB per item and 2 MiB encoded.
- Typing touch state now survives SwiftUI layout rerenders and cancels stale gestures,
  repeaters and asynchronous insertions on later user actions.
- Host and extension settings reconcile before edits to avoid overwriting newer preferences.
- Debug diagnostics and preview helpers compile out of Release.
- Suggestions and autocorrect moved to a post-v1 update.

### Fixed

- Duplicate/missed rollover input, stale shifted/layer actions and physical backspace behavior.
- Double-space rollback after cursor moves, host edits or clipboard insertion.
- Late clipboard saves/insertions and mutation receipts restoring cleared, expired, dismissed
  or Full-Access-revoked UI state.
- Corrupt/future/oversized storage reset, speculative-backup recovery and temporary-file
  cleanup without silently replacing unreadable history.
- CI destination/error handling and device deployment that previously built without installing.

## 0.1.0 — 2026-08-21

Initial native host app and keyboard-extension prototype with QWERTY layouts, shift/caps,
symbols, deletion, cursor slide, long-press callouts, feedback, diagnostics and XcodeGen setup.
