# Release Guide & Checklist

This document details the process for publishing a new version of **The Keyboard Project**.

---

## Pre-Release Checklist

1. **Verify Unit Tests Pass**:
   ```bash
   xcodegen generate
   xcodebuild -project KeyboardProject.xcodeproj \
     -scheme KeyboardProject \
     -sdk iphonesimulator \
     -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO \
     test
   ```

2. **Memory Verification**:
   - Run the keyboard extension on a physical device.
   - Verify using Instruments that `phys_footprint` remains under **40 MB**.

3. **Check Documentation & Changelog**:
   - Ensure [CHANGELOG.md](../CHANGELOG.md) contains all additions, fixes, and changes under the new version header.
   - Ensure [project.yml](../project.yml) `MARKETING_VERSION` matches the target version.

---

## Publishing a Release

1. **Commit & Tag**:
   ```bash
   git add .
   git commit -m "chore(release): prepare v0.1.0"
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin main --tags
   ```

2. **GitHub Release**:
   - Pushing a tag `v*` will automatically trigger the Release GitHub Action (`.github/workflows/release.yml`).
   - Alternatively, draft a release on GitHub and paste the corresponding section from [CHANGELOG.md](../CHANGELOG.md).

3. **Device Deployment / TestFlight**:
   - Open `KeyboardProject.xcodeproj` in Xcode.
   - Select your target device / Any iOS Device (ARM64).
   - Under **Product → Archive**, create an archive for personal device installation or TestFlight distribution.
