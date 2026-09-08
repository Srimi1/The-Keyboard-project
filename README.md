# The Keyboard Project

An iPhone-first, English (US) custom keyboard inspired by Android Gboard's familiar
geometry and clipboard workflow. It is implemented with native Swift, SwiftUI and UIKit,
with no third-party runtime dependencies.

## Status

This repository is a **pre-release device candidate**, not a public release.

| Area | Current state |
|---|---|
| Typing, shift/caps, symbols, deletion, long-press and cursor slide | Implemented with unit and simulator UI coverage |
| VoiceOver key actions and inline settings | Implemented; physical-device acceptance remains open |
| Clipboard history | Manual tap-to-save, consented, bounded and local |
| iPhone deployment | Build/install/verify/launch workflow implemented; must pass on the connected target phone |
| Public launch | Blocked on device acceptance, performance measurements and a 14-day TestFlight beta |

The deployment target remains iOS 16.0. Compatibility at the minimum supported OS and
the current iOS release must be demonstrated before App Store submission.

## v1 scope

- iPhone only, English (US)
- Offline operation with no accounts, analytics, advertising or app-owned networking
- Native four-row keyboard with a real system next-keyboard button
- Haptic setting on by default, sound off by default and system appearance by default
- Persistent tap-to-save clipboard history with pin, unpin, delete and clear-all controls
- Typing and next-keyboard switching without Full Access

Suggestions and autocorrect are deliberately deferred until after a stable public v1.

## Clipboard privacy

Opening the app or keyboard never reads clipboard values. A value is offered to the app
only after the user taps Apple's system Paste button and accepts the local-retention notice.
Automatic capture is disabled.

Recent items expire after one hour. Pinned items remain until unpinned, deleted or history is
cleared. Storage is capped at
50 recent items, 25 pinned items, 16 KiB per item and a 2 MiB encoded file. Files use complete
data protection and are excluded from device backups. Sensitive-content detection is
best-effort and is not a guarantee.

Full Access is optional for typing. It is currently required for the extension to persist
shared clipboard history and for feedback APIs; the host app can manage history directly.

See [the clipboard contract](docs/CLIPBOARD.md) and [privacy policy](docs/PRIVACY.md).

## Build and test

Requirements:

- macOS with Xcode 26 or newer
- XcodeGen 2.45.4
- Python 3 (the Xcode Command Line Tools installation is sufficient)

```bash
make generate
make build
make test
```

The generated `KeyboardProject.xcodeproj` contains the host app, embedded keyboard
extension, unit tests and UI tests. CI builds Debug and Release, runs unit tests and runs
the deterministic typing, deletion, layer and clipboard UI trials separately.

## Install on an iPhone

First sign in under Xcode → Settings → Accounts, connect and trust the iPhone, enable
Developer Mode, and keep the phone unlocked. Then run:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID DEVICE_ID=YOUR_DEVICE_UDID make redeploy
```

If exactly one iPhone is available, `DEVICE_ID` may be omitted. The deployment workflow:

1. resolves one exact physical device;
2. builds the host and embedded extension;
3. validates bundle IDs, signatures, profiles and matching App Group entitlements;
4. installs over the existing app;
5. verifies installation and launches the host app.

After installation, add it at Settings → General → Keyboard → Keyboards → Add New
Keyboard → Keyboard Project. Enable Full Access only if shared clipboard saving and
feedback are wanted.

If you use free Personal Team provisioning, the generated profile is short-lived. Run the
same command to reinstall in place; retention of settings and clipboard history is a required
device acceptance check, not an assumption. See
[the complete installation guide](docs/INSTALLING.md).

## Production gates

The repository is not launch-ready merely because it builds. Release requires:

- a full day of ordinary typing on the target iPhone with user approval;
- real-extension tests for globe switching, permissions, haptics, app switching and
  in-place reinstall;
- measured Release-equivalent extension footprint and input latency;
- a 14-day TestFlight beta with at least three testers, including older/smaller hardware;
- a clean, reproducible signed archive with approved release evidence.

Track these in [the roadmap](docs/ROADMAP.md),
[device acceptance checklist](docs/DEVICE-ACCEPTANCE.md), and
[bug register](docs/BUG-REGISTER.md).

## Repository map

```text
Sources/HostApp/    onboarding, settings, history management and debug preview
Sources/Keyboard/   keyboard extension UI, touch handling and clipboard panel
Sources/Shared/     versioned settings, handshake and clipboard repository
Tests/              deterministic unit and integration-style repository tests
UITests/            host preview and deterministic clipboard UI trials
Scripts/            static verification and physical-device deployment
docs/               architecture, privacy, acceptance and release evidence
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Clipboard contract](docs/CLIPBOARD.md)
- [Roadmap](docs/ROADMAP.md)
- [Release guide](docs/RELEASING.md)
- [Security policy](SECURITY.md)
- [Support](docs/SUPPORT.md)
- [Platform constraints](docs/CONSTRAINTS.md)
- [UI specification](docs/UI-SPEC.md)

Licensed under the [MIT License](LICENSE).
