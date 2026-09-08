# Repository instructions

The Keyboard Project is a native iPhone app plus custom keyboard extension. It is written in
Swift with SwiftUI and UIKit and has no third-party runtime dependencies. `project.yml` is the
project source; `KeyboardProject.xcodeproj` is generated and ignored.

## Start here

1. Read `README.md` and the task-specific document under `docs/`.
2. Inspect `git status` and preserve every existing local change.
3. Generate with `xcodegen generate` after changing `project.yml`.
4. Keep one writer and one serial Xcode/simulator owner in a shared checkout. Read-only review
   may run in parallel.

## Commands

```bash
make generate
make build
make test
./Scripts/verify-static.sh
```

Physical deployment requires an explicit Apple team and target iPhone:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID DEVICE_ID=YOUR_DEVICE_ID make redeploy
```

## Product invariants

- iPhone-only, English (US), iOS 16 minimum until the compatibility gate says otherwise.
- Typing and the next-keyboard control work without Full Access.
- Clipboard reads happen only after an explicit system `PasteButton` action and consent.
- No app-owned networking, accounts, analytics, advertising or clipboard-text logging.
- The keyboard extension never launches the host app or any app other than system behavior
  owned by the next-keyboard control.
- Settings and clipboard failures degrade without breaking typing.
- Suggestions, autocorrect and automatic capture are not v1 features.
- Extension physical footprint target is at most 40 MB, measured on device.

## Engineering rules

- Put runtime code under `Sources/`, tests under `Tests/` or `UITests/`, scripts under
  `Scripts/`, and documentation under `docs/`.
- Validate external text, paths and persisted documents at their boundaries.
- Keep clipboard I/O asynchronous, coordinated and bounded; never log clipboard text.
- Add regression coverage for every fixed bug. Preview UI tests do not replace real-extension
  tests on a physical phone.
- Treat `docs/DECISIONS.md` as an ADR history. Supersede decisions explicitly.
- Never commit secrets, signing identities, provisioning profiles or `.env` files.
- Do not commit, push, tag, publish, delete worktrees or submit a build without explicit user
  authorization. Release evidence and human approval are separate gates.

## Completion standard

A successful build is only a simulator candidate. Installation, daily-use, performance and
TestFlight claims require dated evidence in `docs/DEVICE-ACCEPTANCE.md` and
`docs/release-evidence/` tied to an exact source snapshot.
