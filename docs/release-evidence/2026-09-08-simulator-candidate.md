# Release evidence — 0.1.0 simulator candidate

Release gate: NOT APPROVED

This receipt records a simulator candidate, not a signed archive or public release. Device,
performance, TestFlight, branding and independent-approval gates remain open.

## Exact inputs

| Field | Value |
|---|---|
| Date | 2026-09-08 (Asia/Kolkata) |
| Base Git commit | `d2531bbe1dd6070a8078686bdbe52884379b2c2f` |
| Working tree | Dirty by design; existing and implementation changes were preserved |
| Immutable source snapshot | `KeyboardProject-2026-09-08-simulator-candidate-source.tar.gz`; 99 tracked/untracked, non-ignored files; SHA-256 `099d2a67134d02a72305b2b0bc04e75286a6388a9a2fec8234999faa2aa36eed` |
| Snapshot scope | The receipt itself and ignored generated project are excluded; no runtime/build input changed after the verified builds |
| Version/build | 0.1.0 (1) |
| Deployment target | iPhone, iOS 16.0 minimum |
| Toolchain | Xcode 26.6 (`17F113`), iOS SDK 26.5, macOS 26.6.2 (`25G83`) |
| XcodeGen | 2.45.4; executable SHA-256 `3b483413a801394b00adb2fabf3c06ff8f800c73c8698e1f9a9d8a95d73939ef` |
| Project definition | `project.yml` SHA-256 `fe19951280c35a29ec01708ca1660fdadb603dca9d866b4bb96d536b962f182f` |
| Generated project | Tree digest `748abed341fcc29460c0f49898880b281527a3a10ae073a3c6e1a96de958e2ca` |
| Dependencies | No third-party runtime dependencies |

The immutable source snapshot is retained locally outside the repository as
`KeyboardProject-2026-09-08-simulator-candidate-source.tar.gz`.

## Automated evidence

| Gate | Result | Evidence |
|---|---|---|
| Static privacy/plist/entitlement/script checks | PASS | `./Scripts/verify-static.sh`, 2026-09-08 |
| Whitespace validation | PASS | `git diff --check`, 2026-09-08 |
| Clean Debug simulator build, warnings as errors | PASS | `KeyboardProject-final-debug-20260908-g.xcresult`; zero warnings/errors; tree digest `7d460facab482b1ec2e91d0a0ea88fa6d5cf0a1fad934885c37d77d94791cfcc` |
| Clean Release iPhone-architecture build, warnings as errors | PASS | `KeyboardProject-final-release-20260908-h.xcresult`; zero warnings/errors; tree digest `acffcc05c6732c9fd10f5ea6dbf8a1716a76ccde309ed696dbea7136ad23cbde` |
| Serial unit/integration suite | PASS WITH DEVICE SKIP | 145 total: 144 passed, 1 signed-device-only file-protection check skipped, 0 failed; `KeyboardProject-final-unit-20260908-e.xcresult`; tree digest `3ea5fff3324b41fe32c05b34cbcefd2bbe4b8f2a0be223e26a046b86f376b38d` |
| Deterministic UI suites | PASS | 17 total: 17 passed, 0 failed across typing, backspace, layer and clipboard suites; `KeyboardProject-final-ui-20260908-f.xcresult`; tree digest `f89e1a5b9349d93baf46600247258278e2aef1bb1c1dda60e603ac634aadf0b6` |
| Hosted CI on exact source | FAIL — MISSING | The candidate is an uncommitted working-tree snapshot; no hosted run exists |

## Build iOS Apps simulator verification

The plugin-assisted flow booted the named iPhone 17 simulator, installed the final Debug app,
launched the host and opened the keyboard-preview route. Its browser mirror started, but the
locked Mac prevented browser-surface inspection, so direct Simulator captures were recorded.

| Surface | Result | Evidence |
|---|---|---|
| Host setup | PASS | `KeyboardProject-host-setup.png`; SHA-256 `01de9c1139b24ff70997320a9df8e348b6a3c76d3176d11346661fe5d6589a54` |
| Shared keyboard preview | PASS | `KeyboardProject-keyboard-preview.png`; SHA-256 `9c3023e598394c97d7c055dc227bb4b822df9c1eff856354c41928e20ad58946` |

Both images are beside the source snapshot. Preview success does not verify the real keyboard
extension, document proxy, next-keyboard control, Full Access behavior or device memory.

## Release artifact audit

The audited unsigned Release build product was `KeyboardProject.app`; its tree digest is
`7fa508484942a93107f72906dec8037dc0d377cecb2965509bea9da80ebe806c`.

| Check | Result |
|---|---|
| Host plus embedded keyboard extension | PASS |
| iPhone-only, arm64, iOS 16 minimum, English US keyboard metadata | PASS |
| Privacy manifests parse and declare no tracking/collected data | PASS |
| Third-party frameworks or non-system dynamic dependencies | PASS — none found |
| Test/debug fixtures, local-server markers or extension networking/app-launch indicators | PASS — none found |
| Matching dSYM UUIDs | PASS |
| On-disk size | Host app 3.50 MiB; extension bundle 1.39 MiB |
| Signature and provisioning | FAIL — this generic-device product is unsigned and contains no profiles |
| Signed App Group entitlement match | FAIL — source declarations match, but no signed binary exists to verify |
| Final branding/version | FAIL — 0.1.0 and the generic “Keyboard Project” name remain pre-release values |

## Physical-device and public-release gates

The paired owner iPhone was unavailable to CoreDevice during the deployment attempt, so the
script correctly stopped before install. Connect and unlock it by USB, or make it available on
its paired network, then rerun the signed redeploy workflow.

| Gate | Result |
|---|---|
| Signed install, launch and in-place reinstall on owner iPhone | FAIL — MISSING |
| Real typing, globe, clipboard permissions, VoiceOver and host/extension race matrix | FAIL — MISSING |
| One-day owner typing and layout/feel approval | FAIL — MISSING |
| ≤40 MB runtime footprint, latency/stall targets and 100 lifecycle cycles | FAIL — MISSING |
| iOS 16 and current-iOS physical compatibility | FAIL — MISSING |
| 14-day TestFlight beta with at least three testers | FAIL — MISSING |
| Original branding/store assets and hosted privacy/support URLs | FAIL — MISSING |
| Paid-program archive, independent release review and publishing authorization | FAIL — MISSING |

This receipt was generated before its source-control commit. No tag, archive submission or
publication was performed; repository synchronization is separate from release approval.
