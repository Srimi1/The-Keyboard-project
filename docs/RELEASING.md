# Release guide

No command in this document grants authority to publish. A release owner must separately
approve signing, TestFlight upload and App Store submission.

## 1. Freeze exact source

- Start from a reviewed, clean commit. If local changes are part of the candidate, create an
  immutable snapshot and record its digest; `HEAD` alone is insufficient.
- Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Copy `docs/release-evidence/TEMPLATE.md` to `docs/release-evidence/vX.Y.Z.md`.
- Record Xcode, SDK, XcodeGen, macOS, commit/snapshot and dependency state.

## 2. Automated gates

Use one named iPhone simulator and run serially:

```bash
xcodegen generate
./Scripts/verify-static.sh
xcodebuild clean build -project KeyboardProject.xcodeproj -scheme KeyboardProject \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
xcodebuild clean build -project KeyboardProject.xcodeproj -scheme KeyboardProject \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
xcodebuild test -project KeyboardProject.xcodeproj -scheme KeyboardProject \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -parallel-testing-enabled NO -resultBundlePath UnitTests.xcresult \
  -only-testing:KeyboardProjectTests CODE_SIGNING_ALLOWED=NO
```

Run the asserted UI classes—`TypingTrials`, `BackspaceTrials`, `LayerTrials` and
`ClipboardTrials`—into a separate `.xcresult`. Do not substitute calibration/probe output or
parallel runs for the gate.

## 3. Physical-device gates

- Deploy the exact candidate using [INSTALLING.md](INSTALLING.md).
- Complete [DEVICE-ACCEPTANCE.md](DEVICE-ACCEPTANCE.md) on the target, the minimum supported
  iOS release, current iOS and an older/smaller supported iPhone.
- Record real host/extension concurrency, denied permissions, Full Access revocation and
  in-place reinstall retention.
- Attach Instruments/Points of Interest evidence for footprint, sustained growth, p95 proxy
  latency, main-thread stalls and 100 appearance/dismissal cycles.

Required engineering targets are ≤40 MB extension footprint, no sustained memory growth,
p95 touch-release-to-proxy-call ≤20 ms and no app-owned main-thread stall >100 ms.

## 4. TestFlight and store material

- Use the paid Apple Developer Program and App Store Connect account.
- Complete 14 days with at least three testers, including older/smaller hardware.
- Resolve all crashes, data-loss, privacy and core-use blockers; disclose other limitations.
- Host `PRIVACY.md` and `SUPPORT.md`, link the public URLs in-app and in App Store Connect.
- Finish original icon/branding, screenshots, description, age rating, export-compliance and
  privacy disclosures.
- Recheck Apple's current submission/Xcode/SDK requirements on release day.

## 5. Archive and approval

Create the distribution archive in Xcode Organizer from the exact approved source. Inspect the
archive—not a Debug product—for:

- host and extension identities/profiles/App Group entitlements;
- bundled privacy manifests;
- absence of Debug diagnostics, probes and test fixtures;
- no unexpected frameworks, network code or clipboard logging;
- archive/export checksums tied to the evidence file.

The manual `Draft release` workflow validates the version and an evidence file containing the
exact line `Release gate: APPROVED`. It creates only a prerelease draft behind the
`public-release` environment. It does not upload or submit an App Store build.

Only after independent human approval may the release owner tag, upload or submit. Never use
blanket staging commands such as `git add .` in release instructions; review the exact diff.
