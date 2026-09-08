# Install on an iPhone

## Requirements

- A Mac with Xcode 26 or newer and XcodeGen 2.45.4.
- Python 3; the version installed with Xcode Command Line Tools is sufficient.
- An Apple ID signed in under Xcode → Settings → Accounts.
- An unlocked, trusted iPhone connected by USB or the same paired Wi-Fi.
- Developer Mode enabled under Settings → Privacy & Security for development builds.
- The signing Team ID shown by Xcode.

A free Personal Team is the first installation route, but its App Group/profile capabilities
must pass the script checks on the target account. Free provisioning normally expires after
seven days and cannot distribute through TestFlight or the App Store.

## Build, verify, install and launch

Find the phone in Xcode's Devices and Simulators window, then run:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID DEVICE_ID=YOUR_DEVICE_ID make redeploy
```

If exactly one physical iPhone is available, omit `DEVICE_ID`. The script fails instead of
guessing when selection is ambiguous. It generates the project, builds both targets, checks
bundle IDs/signatures/profiles/App Group entitlements, installs with `devicectl`, verifies the
host app is present and launches it.

The first signed build may require Settings → General → VPN & Device Management → Developer
App → Trust. There is no programmatic bypass.

## Enable the keyboard

1. Open Settings → General → Keyboard → Keyboards.
2. Tap Add New Keyboard and choose Keyboard Project.
3. Switch to it from a normal text field using the globe key.
4. Optional: open the Keyboard Project entry and enable Allow Full Access for shared local
   clipboard history and feedback. Plain typing and globe switching work without it.
5. Open the host app, accept the clipboard retention notice and use Save current clipboard to
   test history.

iOS may replace custom keyboards in password/secure and phone-pad fields, and individual apps
may prohibit them. Test in Notes before diagnosing those expected restrictions.

## Reinstall

Run the same command. It installs over the current bundle and is intended to preserve App Group
history and settings, but preservation is not considered verified until the before/after values
are recorded in [DEVICE-ACCEPTANCE.md](DEVICE-ACCEPTANCE.md). Do not uninstall the app for this
test because uninstalling can remove its data.

## Interpreting failures

- “paired but unavailable”: unlock the phone and reconnect USB/Wi-Fi.
- profile/App Group mismatch: select the correct team in Xcode and let automatic signing update
  both targets; if the Personal Team cannot provision the group, a paid team is required.
- launch rejected after install: trust the developer certificate on the phone.
- no keyboard in Add New Keyboard: verify the embedded extension exists and both profiles are
  valid; rerun the script for its specific check.
