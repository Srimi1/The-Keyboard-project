# Release evidence — vX.Y.Z

Release gate: NOT APPROVED

Change the line above to `Release gate: APPROVED` only after an independent release owner has
reviewed every required artifact. Missing evidence is FAIL, not N/A, unless this template
explicitly permits N/A.

## Exact inputs

| Field | Value |
|---|---|
| Git commit | |
| Working tree clean | |
| Immutable snapshot/hash if dirty | |
| Version/build | |
| Xcode build | |
| iOS SDK | |
| XcodeGen + checksum | |
| Dependency resolution | No third-party runtime dependencies / verify |
| Generated-project hash | |

## Automated evidence

| Gate | PASS/FAIL | Command, `.xcresult` or log, timestamp |
|---|---|---|
| Static privacy/plist/entitlement/script checks | | |
| Debug simulator build, warnings as errors | | |
| Release iPhone-architecture build, warnings as errors | | |
| Complete serial unit suite | | |
| Typing/backspace/layer UI suite | | |
| Clipboard UI suite | | |
| Hosted CI on exact commit | | |

## Signing and archive

| Field | Value/evidence |
|---|---|
| Archive path and SHA-256 | |
| Export artifact and SHA-256 | |
| Host identity/profile/expiry | |
| Extension identity/profile/expiry | |
| Matching App Group entitlements | |
| Privacy manifests in both final bundles | |
| Debug/test tools absent | |
| Unexpected frameworks/network/logging audit | |

## Device matrix

| Device | iOS | Install/reinstall | Typing/globe | Clipboard/permissions | VoiceOver | Result |
|---|---|---|---|---|---|---|
| Owner target | | | | | | |
| Older/smaller iPhone | | | | | | |
| Minimum supported iOS | | | | | | |
| Current iOS | | | | | | |

Attach completed `DEVICE-ACCEPTANCE.md` copies or links. Record real host/extension concurrent
writes and retained data after in-place reinstall.

## Performance

| Measure | Target | Result | Trace |
|---|---:|---:|---|
| Sustained-typing footprint | ≤40 MB | | |
| Maximum-history footprint | ≤40 MB | | |
| Sustained growth | none | | |
| Touch release → proxy call p95 | ≤20 ms | | |
| App-owned main-thread stall | none >100 ms | | |
| 100 appearance/dismissal cycles | no crash/growth | | |

## TestFlight

Start/end dates: __________ / __________ (at least 14 days)

Tester count: __________ (at least 3)

Crashes: __________  Data-loss/privacy/core-use blockers: __________

Resolved bug IDs and disclosed non-blocking limitations: __________

## Store and policy

- [ ] Original icon, branding and current-device screenshots approved.
- [ ] Public privacy-policy and support URLs reachable in-app and in listing.
- [ ] App privacy disclosures match actual code/data flow.
- [ ] Current App Review and upload/SDK requirements rechecked with links/date.
- [ ] Age rating, description, export compliance and review notes complete.
- [ ] No unresolved P0/P1 or release-blocking Gate item.

## Independent approval

Reviewer: __________  Date: __________

Decision/rationale: __________

Submission/publishing authorization (separate from technical approval): __________
