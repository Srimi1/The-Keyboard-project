# iPhone-first production roadmap

This roadmap separates implemented code from evidence that can only come from a signed
keyboard extension on physical iPhones. A green simulator build is not a public-release gate.

## Product target

v1 is an iPhone-only, English (US), offline keyboard with dependable tap typing and an
explicit, local clipboard history. It has no accounts, analytics, advertising or app-owned
networking. Suggestions, autocorrect, automatic clipboard capture, glide typing and cloud
features are post-v1 work.

The deployment target remains iOS 16.0 until the minimum-OS test matrix proves it supportable.

## Current position

| Workstream | State |
|---|---|
| Native host app and embedded keyboard extension | Implemented |
| Typing, layers, caps, deletion, long-press accents and spacebar cursor movement | Automated coverage; physical feel test open |
| Next-keyboard control and VoiceOver actions | Implemented; physical verification open |
| Persistent haptic, sound, appearance and clipboard preferences | Implemented |
| Manual clipboard save/history/pin/delete/clear/expiry | Implemented with failure-path tests |
| Signed install/reinstall workflow | Implemented; target-iPhone execution open |
| Performance, one-day use and TestFlight evidence | Open |

The exact open defects and evidence gaps live in [BUG-REGISTER.md](BUG-REGISTER.md).

## Phase 1 — trustworthy candidate

- Preserve the existing working tree and bind evidence to an exact commit or immutable dirty
  snapshot.
- Generate the project from `project.yml`; run static policy checks.
- Treat Swift/compiler warnings as errors in Debug simulator and unsigned Release
  iPhone-architecture builds. Record any Xcode-owned external-tool diagnostic separately; it
  must not hide an app, extension or concurrency warning.
- Run all unit tests serially against one named simulator.
- Run deterministic typing, deletion, layer and clipboard UI suites serially.
- Keep the dependency-free Swift/UIKit/SwiftUI architecture.

Exit: all automated gates pass from the same source snapshot, with `.xcresult` locations and
build logs recorded. No physical-device claim is made here.

## Phase 2 — target iPhone installation

- Connect and unlock the target iPhone; confirm pairing and Developer Mode.
- Select the exact device and signing team, then run `Scripts/redeploy.sh`.
- Verify host and extension signatures, provisioning profiles and matching App Group
  entitlements before install.
- Verify the app is installed and launches, then add the keyboard in Settings.
- Repeat the install over the existing app and verify settings/history retention manually.

Exit: every item in [INSTALLING.md](INSTALLING.md) and the installation section of
[DEVICE-ACCEPTANCE.md](DEVICE-ACCEPTANCE.md) has dated evidence.

## Phase 3 — daily-use acceptance

- Use Notes, Messages drafts and Safari for a full ordinary day.
- Verify globe switching, real document-proxy edits, rotation/dismissal, permission prompts,
  Full Access revocation, haptics/sound and all clipboard controls.
- Compare the actual globe-key layout and long-press behavior with the owner's Android Gboard
  references; record and fix muscle-memory misses.
- Exercise denied paste permission and password-manager/local-only providers.
- Run real host/extension concurrent-write and clear-versus-save trials.
- Measure a Release-equivalent extension under sustained typing, maximum history, and 100
  appearance/dismissal cycles.

Engineering targets: physical footprint at or below 40 MB, no sustained growth, p95
touch-release-to-proxy-call at or below 20 ms, and no app-owned main-thread stall above 100 ms.

Exit: the owner signs the device checklist; there are no open crash, data-loss, privacy or
core-typing defects.

## Phase 4 — public release candidate

- Join the paid Apple Developer Program and configure App Store Connect.
- Host the privacy and support pages and place their public URLs in the app and listing.
- Replace provisional branding/screenshots with original release assets.
- Run a 14-day TestFlight beta with at least three people, including an older/smaller supported
  iPhone and both the minimum and current supported iOS releases.
- Re-audit App Review rules, privacy manifests, entitlements, logs and data disclosures.
- Produce a reproducible signed archive with Debug-only tools absent and evidence bound to its
  exact source and archive checksum.

Exit: every required row in `docs/release-evidence/` is PASS, known non-blocking limitations
are disclosed, and a human release owner explicitly approves submission. Automation may draft
a release; it does not publish the App Store build.

## After v1

Evaluate suggestions/autocorrect first, then automatic capture only if permission and
password-manager trials show a trustworthy experience. Each requires a new device, privacy
and memory review before entering the shipping scope.
