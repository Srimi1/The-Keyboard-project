# v1 keyboard refinement — 2026-09-13

Release gate: NOT APPROVED

This is local simulator evidence. No physical-phone installation, permission, audio,
haptic comfort, performance, daily-use or TestFlight acceptance is claimed.

## Candidate

- Base commit: `b8117c8a4a5516085f0a69470275d7c6b92d9874`.
- Working tree: intentionally dirty; pre-existing branding and motion changes preserved.
- Source manifest: [2026-09-13-v1-source.sha256](2026-09-13-v1-source.sha256).
- Manifest SHA-256: `42aa46b0335194c11bd7d985b286e20aa1bfa2a69a26b3f83d5d540ebc14940e`.
- Local source archive: `.build/evidence/2026-09-13-v1-source.tar.gz`.
- Archive SHA-256: `a219dab5733f11b818eec8e16f13e2ee0f8d38afce56d0601ec44f6f3b0cdc54`.
- Simulator: KBProject-iPhone17, iOS 26.5, `18BBE556-B31C-42CE-8211-00F4D360B4AC`.

## Scope

Setup completion is remembered independently of clipboard consent. Existing users with a
keyboard-use handshake skip the checklist; anyone can dismiss or review it. iOS still owns
adding the keyboard and granting Full Access. No system permission is granted automatically.

The keyboard toolbar contains Clipboard and Settings. Debug diagnostics move into settings
and the stethoscope/memory readout is removed. Clipboard has an explicit system Paste control,
recent/pinned cards, tap-to-insert, long-press pin/delete, and confirmed clear-all inside the
keyboard. Consent and settings persist. Full Access limitations appear before the consent
prompt, and privacy details remain accessible inside the keyboard. Capture stays manual.

Haptic intensity varies with key action and typing cadence. New installs enable system key
clicks; existing stored preferences are preserved. Shift/caps lock, symbols, long-press
alternates, held delete, auto-capitalization, double-space punctuation, cursor sliding and the
real system next-keyboard button remain the v1 typing foundation. Suggestions, autocorrect,
glide typing, dictation and a custom emoji catalog are outside this refinement; system
keyboard switching remains available.

Research: [Google's clipboard help](https://support.google.com/gboard/answer/10742542?hl=en)
and [Apple's explicit paste control](https://developer.apple.com/documentation/uikit/uipastecontrol).
This adapts the documented interaction pattern to iOS; it does not reproduce Gboard internals
or add Android-style automatic clipboard capture.

## Validation

- Debug simulator build: PASS; zero compiler warnings/errors.
- Release simulator build: PASS with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and
  `GCC_TREAT_WARNINGS_AS_ERRORS=YES`; zero compiler warnings/errors.
- Static privacy, entitlements, plists, shell and branding: PASS.
- Source manifest verification and `git diff --check`: PASS.
- Unit/integration suite: 152 executed, 151 passed, one signed-device-only file-protection
  test skipped, zero failures. Includes adaptive feedback and settings migration/consent.
- Setup UI: one passed (dismiss, relaunch, review, no implied clipboard consent).
- Existing host clipboard UI: three passed (notice-before-save, explicit capture, deduplication).
- Final keyboard/typing UI run: 15 passed, zero failed/skipped: Backspace 3, Layers 4,
  Typing 7, and keyboard clipboard 1. The new clipboard trial proves actual text insertion,
  direct clear-all, persistent consent, and independent toolbar accessibility identifiers.

Total UI coverage: 19 passing tests across the runs above. The unit/setup run predates the
final UI-only identifier correction; the final 15-test run covers that correction. The first
UI attempts exposed a lazy-list navigation assumption and a propagated container identifier;
both were corrected before their corresponding passing reruns. No test failure remains open.

Local XcodeBuildMCP artifacts are under
`/Users/srimi/Library/Developer/XcodeBuildMCP/workspaces/the-Keyboard-Project-cb79392f0f84/`:

| Evidence | Artifact beneath that directory |
|---|---|
| Initial Debug build | `logs/build_sim_2026-09-12T19-56-18-065Z_pid39286_d323740b.log` |
| Unit/setup results (includes the superseded UI failures) | `result-bundles/test_sim_2026-09-12T19-58-33-167Z_pid39286_e14e906e.xcresult` |
| Passing three host clipboard trials (includes the superseded toolbar-identifier failure) | `result-bundles/test_sim_2026-09-12T20-02-49-559Z_pid39286_f5ecc1ba.xcresult` |
| Final 15 passing UI trials | `result-bundles/test_sim_2026-09-12T20-08-41-139Z_pid39286_4cbba554.xcresult` |
| Release build | `logs/build_sim_2026-09-12T20-15-13-943Z_pid39286_637d15e5.log` |

The final UI tool request exceeded its 300-second response timeout, but the underlying Xcode
run completed. Its `.xcresult` summary independently reports **Passed, 15 passed, 0 failed**.
A simulator launch helper initially selected the extension as the installable app; installing
the explicit `KeyboardProject.app` path succeeded. Neither tooling issue is a product failure.


## Required phone follow-up

Use [DEVICE-ACCEPTANCE.md](../DEVICE-ACCEPTANCE.md) with this source snapshot. Specifically
check keyboard installation, real Full Access/paste Allow/Ask/Deny, consent retention through
extension relaunch and reinstall, clipboard pin/unpin/delete/clear across processes, and
adaptive haptics/system clicks with Silent Mode and the system keyboard-click preference.
No signed deployment was performed in this task.
