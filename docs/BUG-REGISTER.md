# Bug and launch-blocker register

Severity: P0 data/privacy catastrophe or unusable keyboard; P1 crash/data loss/core typing;
P2 important degradation; Gate evidence that cannot be produced by simulator code.

## Fixed in the current candidate

| ID | Sev | Reproduction before fix | Regression/evidence | Status |
|---|---:|---|---|---|
| KB-001 | P1 | A second finger lands while Shift/layer rerenders; release uses a stale action and misses or changes case | `KeyboardTouchTests` stale-layout rollover cases | Fixed; automated |
| KB-002 | P1 | Double-space converts to period, caret/host context moves, then Backspace rewrites unrelated text | double-space caret/context/clipboard regressions | Fixed; automated |
| KB-003 | P1 | Delayed clipboard insertion completes after a later key, caret move, panel or lifecycle change | suspended-insertion ordering tests | Fixed; automated |
| KB-004 | P1 | Held letter/backspace overlaps a paste-chip tap, reordering input or leaving repeat active | held-touch clipboard ordering tests | Fixed; automated |
| KB-005 | P1 | Delayed save/mutation restores cleared or Full-Access-revoked UI/history | controller epoch/generation and clear-fence tests | Fixed; automated |
| KB-006 | P1 | Corrupt/future storage is silently replaced or speculative backup resurrects data | repository corruption/fence/reset tests | Fixed; automated |
| KB-007 | P2 | One process edits a stale settings record and overwrites another preference | two-store distinct-field test | Fixed; automated |
| KB-008 | P1 | Deploy command builds but never installs | script now verifies, installs, confirms and launches | Fixed in script; device run open |
| KB-009 | P1 | CI passes broken destinations or swallows failures | pinned serial CI and explicit simulator selection | Fixed; hosted CI run open |
| KB-010 | P2 | `make test` assumes a simulator literally named `iPhone 17`, while local/CI runtimes may use another name | selector prefers the booted iPhone and passes its exact UDID | Fixed; automated command |
| KB-011 | P2 | Static gate never inspected the app-icon catalog: a missing, mis-sized, transparent or stale `AppIcon.appiconset` entry passed silently | `Scripts/verify-branding.sh` catalog checks (existing opaque 1024×1024 PNG, no stale files) | Fixed; automated |
| KB-012 | P2 | Static gate never checked `assets/branding/manifest.json` references: a dangling `source`/`export`/`archivedExport` passed silently | `Scripts/verify-branding.sh` manifest-reference existence checks | Fixed; automated |
| KB-013 | P2 | Static gate never enforced the monochrome contract: a chromatic pixel or non-black/white SVG color passed silently | `Scripts/verify-branding.sh` achromatic PNG (full PNG unfilter, stdlib only) and SVG palette checks | Fixed; automated |
| KB-014 | P2 | Manifest tracked only `exports/app-icon-1024.png`, leaving the preview PNGs and the shipping catalog icon untracked so renderer drift went unnoticed | manifest `previewExports`/`activeIcon`/`rendererOutputs` plus renderer-output and byte-identity checks | Fixed; automated |
| KB-015 | P0 | Local working tree and most of `.git`'s object database silently lost data: 25 tracked files (`KeyboardTheme.swift`, `ClipboardPanel.swift`, `KeyboardSettingsPanel.swift`, `KeyboardIconography.swift`, `ClipboardItem.swift`, `ClipboardStore.swift`, `ClipboardHistory.swift`, `KeyboardSettings.swift`, three `HostApp` views, both `.github/workflows/*.yml`, the app-icon PNG and all of `assets/themes/`) vanished from disk with no corresponding git deletion, and `HEAD`'s own commit object was missing from `.git/objects` (`git status` failed with `fatal: bad object HEAD`; `git fsck` reported hundreds of missing blobs/trees). The repository lives under `~/Library/Mobile Documents/com~apple~CloudDocs/…` (iCloud Drive); `brctl status` showed the container mid-sync with repeated failed "apply changes" attempts, and duplicate `" 2"`-suffixed macOS conflict copies of the exact missing files appeared moments after recovery — both point at an iCloud sync/eviction fault racing with local writes, not an intentional deletion (the surviving code still actively references every missing type). | Recovered by fetching `origin/main` over HTTPS (the configured `git@github.com` SSH remote has no authorized key in this environment) to repopulate the object store, then `git restore` for the 25 missing paths; verified byte-identical against the iCloud-delivered `" 2"` duplicates before deleting them. Clean Debug/Release builds, 147/147 unit tests (1 expected signed-device-only skip) and the real-touch `TypingTrials`/`LayerTrials`/`BackspaceTrials`/`ClipboardTrials` UI suites all pass afterward. | Fixed; recovered from `origin/main` |
| KB-016 | P2 | Every host launch repeats the full setup checklist, with no way to dismiss it permanently | `SetupTrials` relaunch/review flow and settings persistence/legacy migration tests | Fixed; simulator; device retention open |
| KB-017 | P2 | Debug keyboard exposes the stethoscope and memory/globe instrumentation while typing | toolbar UI regression; diagnostics moved to Debug settings | Fixed; simulator; device appearance open |
| KB-018 | P2 | Clipboard panel says to tap Save although the system control says Paste, lacks direct clear-all, and presents consent ahead of a Full Access limitation | keyboard clipboard UI trial plus existing controller access-revocation regressions | Fixed; simulator; real-extension permissions open |
| KB-019 | P2 | The theme identifier on the root SwiftUI container overwrites toolbar and clipboard control identifiers | keyboard clipboard UI trial targets each control by its own identifier | Fixed; keyboard clipboard UI trial passed |

For a regression, add its exact steps, expected/actual behavior and a failing test before the
fix where practical. Do not close from code inspection alone.

## Open release blockers

Current evidence on 2026-09-09: clean Debug and Release builds report zero compiler
warnings or errors; 146 of 147 unit/integration tests passed with the signed-device-only
file-protection check skipped, and all 17 deterministic UI tests passed. The host app and
keyboard preview installed and launched on an iPhone 17 simulator. The target iPhone is paired,
but was unavailable to CoreDevice during deployment, so no physical-device gate is closed.

Second-pass local evidence on 2026-09-10 (same checkout, branding mitigation only): the
brand renderer was re-run and is byte-deterministic (all four PNG hashes unchanged); the new
`Scripts/verify-branding.sh` gate passes (catalog references an existing opaque 1024×1024
PNG with no stale entries, all manifest-referenced files exist, production PNGs are fully
achromatic, SVGs use only `#000000`/`#FFFFFF`, renderer outputs exist and both 1024 icons are
byte-identical); clean Debug (iOS Simulator) and Release (iPhone-architecture) builds report
zero warnings or errors; 147 unit/integration tests passed with the same 1 signed-device-only
skip and 0 failures; all 17 deterministic UI tests passed serially (Typing 7, Backspace 3,
Layer 4, Clipboard 3) with 0 failures. No physical-device claim is made here: physical iPhone
approval, trademark/name-mark clearance, real-device screenshots, signing, daily-use,
performance and TestFlight gates all remain open.

| ID | Sev | Required reproduction/check | Closure evidence |
|---|---:|---|---|
| GATE-001 | Gate | Deploy exact candidate to the target iPhone | successful script log plus device checklist |
| GATE-002 | Gate | One full ordinary typing day and owner layout/feel approval | signed device acceptance |
| GATE-003 | Gate | Real proxy/globe/permissions/VoiceOver/reinstall and host-extension races | dated physical-device matrix |
| GATE-004 | Gate | Release-equivalent memory, latency, stalls and 100 lifecycle cycles | Instruments/traces meeting all targets |
| GATE-005 | Gate | iOS 16 minimum and current-iOS compatibility | device/TestFlight results or raised minimum |
| GATE-006 | Gate | 14-day beta with ≥3 testers including older/smaller iPhone | TestFlight report with no blocking issues |
| GATE-007 | Gate | Original store assets and hosted privacy/support URLs | final metadata/screenshots/reachable URLs |
| GATE-008 | Gate | Paid program, final archive/privacy/entitlement audit | approved release-evidence file and archive hash |

## Known non-bugs/limitations

- iOS replaces custom keyboards in some secure/phone-pad fields and apps may prohibit them.
- Automatic clipboard capture, suggestions/autocorrect and glide typing are not v1 features.
- Sensitive markers are best-effort, not guaranteed secret detection.
- Simulator previews cannot validate extension memory, Full Access, globe behavior, paste
  prompts, file-protection attributes or real document-proxy timing.

## Environment risk: this checkout lives inside iCloud Drive

KB-015's root cause is environmental, not a code defect, and is not closed by fixing one
incident: `git`'s object store is thousands of small loose files, which is a known bad
interaction with iCloud Drive's per-file sync/eviction. Recommended mitigations, not yet
applied:

- Move the working checkout outside any `~/Library/Mobile Documents/…` path (a plain
  `~/Developer/…` directory), or at minimum add `.git/` to iCloud's exclusion list.
- Restore the `origin` remote's push access: `git@github.com` SSH failed with `Permission
  denied (publickey)` in this environment (no authorized key for this host), so this recovery
  used an anonymous HTTPS fetch. Either add a deploy key or switch `origin` to HTTPS with the
  already-authenticated `gh` credential helper.
- Run `git fsck` before trusting `git status`/`git log` after any period the checkout may have
  been mid-sync; a ref pointing at a missing object fails cleanly today, but silent partial
  file loss without an object-store check would not.

## 2026-09-13 v1 refinement evidence

[Candidate, source hashes, test results and remaining phone checks](release-evidence/2026-09-13-v1-refinement.md).
Debug and Release simulator builds pass; unit/integration tests have zero failures (one
device-only skip), and all 19 selected UI trials passed across their final runs.
