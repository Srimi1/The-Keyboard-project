# Privacy policy

Last updated: September 8, 2026

The Keyboard Project is an offline custom keyboard. The developer does not collect, receive,
sell or share what you type, clipboard history, settings, identifiers, diagnostics or usage
analytics. The app has no account system, advertising SDK, analytics SDK or app-owned network
service.

## Typed text

Typed text is sent by iOS to the app you are typing in through Apple's keyboard-extension
interface. The Keyboard Project does not store typed text and does not transmit it to the
developer. iOS may prevent third-party keyboards from appearing in sensitive fields.

## Clipboard history

The app does not inspect the clipboard when it launches, enters the foreground or shows the
keyboard. A clipboard value is provided only after you accept the local-retention notice and
tap Apple's system Paste button.

Saved text stays in the app's local shared container on that iPhone. Recent items expire after
one hour; pinned items remain until you unpin/delete them or clear history. Items may be
shortened to 16 KiB and total history is bounded. Files are excluded from backups and use iOS
complete data protection. Clipboard text is not intentionally logged.

Sensitive-content signals from other apps are checked, but no detector can identify every
password, token or secret. Do not save secrets to history. You can delete one item or clear all
history in either the host app or keyboard while shared access is available.

## Full Access

Plain typing and switching keyboards do not require Full Access. iOS Full Access is optional
and is used for local App Group clipboard sharing and keyboard feedback. Enabling it grants a
keyboard broader operating-system capability, but this app does not use that capability for
network communication. If Full Access is revoked, the extension hides cached history because
it can no longer verify whether the host app deleted it.

## Settings and diagnostics

Haptic, sound, appearance, clipboard-consent and setup-status values are stored locally.
Development diagnostics are excluded from Release builds. Apple may independently process
App Store or TestFlight information under Apple's policies.

## Deletion and changes

Use Clear all to remove clipboard history. Removing the app removes its local app data under
iOS behavior. Material policy changes will update the date and ship with release notes.

## Contact

Use the private channel described in [SUPPORT.md](SUPPORT.md) for privacy requests or the
repository's private security advisory form for a vulnerability. Do not include real clipboard
contents or credentials in a report.
