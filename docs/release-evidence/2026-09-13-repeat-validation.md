# Repeated simulator validation — 2026-09-13

Release gate: NOT APPROVED. Physical-device acceptance remains open.

## Source and environment

- Base commit: `b8117c8a4a5516085f0a69470275d7c6b92d9874`; existing local changes preserved.
- Simulator: KBProject-iPhone17, iOS 26.5,
  `18BBE556-B31C-42CE-8211-00F4D360B4AC`.
- Final source manifest: [2026-09-13-repeat-validated-source.sha256](2026-09-13-repeat-validated-source.sha256),
  98 files; SHA-256 `9b990e86412f01782ca623ec250d9b333b441fb5abb81476313805c14b9d6839`.
- Local source archive: `.build/evidence/2026-09-13-repeat-validated-source.tar.gz`;
  SHA-256 `ac39350d732a32809f62283f868ec104025ef0fe8989ea9d603afa590b29754b`.
- Runtime source is unchanged from [the v1 refinement](2026-09-13-v1-refinement.md).
  This follow-up adds one clipboard UI regression trial and evidence.

## Runs

Each full round runs all 152 unit/integration tests and 20 UI tests serially. UI tests launch
the host preview; clipboard/setup trials use isolated stores with synthetic text. They do
not exercise another app's real keyboard extension or system paste authorization.

| Run | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Full round 1 | 170 | 1 | 1 | New trial assumed a Cancel button; test corrected |
| Targeted recheck 1 | 0 | 1 | 0 | Background element tap blocked by popover; test corrected |
| Targeted recheck 2 | 0 | 1 | 0 | Final key queried as Button rather than keyboard key; test corrected |
| Targeted recheck 3 | 1 | 0 | 0 | Expanded clipboard sequence passed |
| Full round 2 | 171 | 0 | 1 | Passed |
| Full round 3 | 171 | 0 | 1 | Passed |

Both final full rounds passed all 151 simulator-eligible unit/integration tests and all
20 UI tests. The skipped case requires signed-device file protection. No application-code
defect was reproduced in these runs. Initial failures were in the newly added UI test's
interaction assumptions, not dismissed or removed assertions. The first round's source is
preserved in [2026-09-13-repeat-source.sha256](2026-09-13-repeat-source.sha256) and
`.build/evidence/2026-09-13-repeat-source.tar.gz`.

The clear-all dialog on this simulator is a native popover with outside-tap dismissal.
The test now handles either a visible Cancel button or an outside coordinate obtained from
the observed preview-text frame, and waits for the dialog to disappear before asserting
the clip survived. This matches the platform-dependent behavior described by
[Apple's confirmation-dialog documentation](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)-87n66).
The final typing assertion uses the existing keyboard-key accessibility identifier across
element types, as the other typing trials do.

## Behaviors exercised

- Setup completion survives terminate/relaunch; reviewing setup does not grant clipboard consent.
- Clipboard notice precedes capture; explicit fixture capture saves once; duplicate saves deduplicate.
- The keyboard panel inserts saved text, clears history with confirmation, remembers consent,
  and has no stethoscope control.
- The new trial pins a clip, cancels clear-all without losing it, switches through keyboard,
  settings and clipboard five times, unpins and deletes it, verifies the empty state on
  reopening, and types `A`. Its final text assertion also detects accidental menu-action paste.
- UI typing covers every row, auto-capitalization, shift/caps lock, space, rollover, single
  and held delete, digits, extended symbols and returning to letters.
- Unit/integration coverage includes adaptive feedback intensity and cadence, settings
  migration and persistence, clipboard limits, expiry, recovery, and cancellation/race handling.

The expanded clipboard trial passed three complete executions (targeted recheck 3 and
full rounds 2 and 3), totaling 15 panel-switch cycles followed by successful typing.
Debug build-for-testing, static privacy/entitlement/plist/branding/shell checks,
`git diff --check`, and verification of all 98 final source hashes passed.

## Artifacts

All local result bundles, logs and JSON summaries are beneath
`.build/repeat-validation/20260913-021156/`: `round-1`, `round-2`, `round-3`,
`clipboard-recheck`, `clipboard-recheck-2`, and `clipboard-recheck-3`.
Each name has a `.log` and `.xcresult`; full rounds also have `-summary.json`.
Debug build-for-testing logs are under `.build/repeat-validation/`.

Screenshots from the passing targeted trial:

- [Clear-all confirmation](2026-09-13-repeat-screens/clear-all-confirmation.png).
- [Typing after repeated panel switches](2026-09-13-repeat-screens/typing-after-panel-cycles.png).

XcodeBuildMCP rejected the configured scheme despite reporting it in session defaults;
serial `xcodebuild build-for-testing` and `test-without-building` were used successfully.
The test source was rebuilt after each harness correction; final rounds 2 and 3 used the
same generated `.xctestrun` under `/tmp/keyboard-v1-derived/Build/Products/`, with
`-parallel-testing-enabled NO` and the exact simulator ID above. No runtime source changed.
Captured UI screenshots were visually reviewed. A separate native-computer interaction
attempt could not complete because the Mac was locked; no additional manual UI pass is claimed.

## Remaining boundary

These runs do not establish minimum-iOS compatibility, real Full Access/paste Allow/Ask/Deny,
cross-process extension retention, actual globe switching, audible clicks, haptic comfort,
Silent Mode behavior, memory footprint, daily-use acceptance, or TestFlight readiness.
Use [DEVICE-ACCEPTANCE.md](../DEVICE-ACCEPTANCE.md) against the final source snapshot.
No physical-device deployment, commit, push or release was performed.
