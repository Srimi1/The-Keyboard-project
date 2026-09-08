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

For a regression, add its exact steps, expected/actual behavior and a failing test before the
fix where practical. Do not close from code inspection alone.

## Open release blockers

Current evidence on 2026-09-08: clean Debug and Release builds report zero compiler
warnings or errors; 144 of 145 unit/integration tests passed with the signed-device-only
file-protection check skipped, and all 17 deterministic UI tests passed. The host app and
keyboard preview installed and launched on an iPhone 17 simulator. The target iPhone is paired,
but was unavailable to CoreDevice during deployment, so no physical-device gate is closed.

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
