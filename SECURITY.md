# Security policy

## Supported builds

There is no public production release yet. Security fixes target the latest source and active
TestFlight candidate; old development-signed builds are not supported.

## Privacy and security boundary

- The app and keyboard contain no app-owned networking, tracking, analytics or advertising.
- Clipboard values are supplied only after an explicit system Paste button action.
- History is stored in the local App Group container, excluded from backups and written with
  complete data protection on iPhone.
- Typing works without Full Access. Full Access is used only for shared local clipboard storage
  and feedback behavior.
- Clipboard text is never intentionally logged.
- Sensitive-content markers are best-effort and cannot identify every secret. Do not save a
  password or other secret to history; delete it immediately if saved accidentally.

## Reporting a vulnerability

Do not post clipboard or security details in a public issue. Use the repository's
[private security advisory form](https://github.com/Srimi1/The-Keyboard-project/security/advisories/new).
Include the affected build/source revision, iOS/device, reproduction steps and impact, but
redact real clipboard contents, credentials and signing data.
