# Physical-device acceptance

Record date, source snapshot, build configuration, iPhone model and iOS version for every run.
Do not mark a row PASS from the host preview or simulator.

## Installation and permissions

- [ ] Signed host and embedded extension pass profile/signature/App Group checks.
- [ ] `devicectl` installs and the host app launches.
- [ ] Keyboard appears in Add New Keyboard and the real globe control switches both ways.
- [ ] Plain typing and globe switching work with Full Access off.
- [ ] Full Access enable/revoke is reflected without restart or stale clipboard content.
- [ ] Paste permission Allow, Ask and Deny paths show accurate, recoverable UI.
- [ ] Password-manager, concealed and local/expiring provider trials do not retain secrets.
- [ ] In-place redeploy retains a named setting and harmless test history item.

## Typing and accessibility

- [ ] Notes: ordinary prose, caps lock, double-space/backspace, selection moves and long delete.
- [ ] Messages draft: fast rollover produces no missed, duplicated or reordered characters.
- [ ] Safari: URL/search traits and return labels behave correctly.
- [ ] Symbol/extended layers and long-press accent/punctuation selection match expectations.
- [ ] Spacebar movement edits the intended caret position and never triggers a stale paste.
- [ ] Rotation, panel changes, app switches and 100 appearance/dismissal cycles leave no stuck
  key, deletion repeater, callout or delayed insertion.
- [ ] Haptic/sound toggles and system/light/dark appearance persist.
- [ ] VoiceOver can activate letters, functions, clipboard items and settings; typing remains
  usable with multitouch when VoiceOver is off.
- [ ] Owner completes one full day without switching because of a keyboard defect and approves
  layout, long-press behavior and typing feel.

## Clipboard

- [ ] First save explains local retention and nothing is captured before explicit Save.
- [ ] Save/paste/pin/unpin/delete/clear behave correctly across host and extension.
- [ ] 50 recent, 25 pinned, one-hour expiry, 16 KiB item and 2 MiB file behaviors are verified.
- [ ] Clear versus delayed save cannot restore content; expiry removes visible and stored text.
- [ ] Corrupt/unavailable App Group states preserve data or allow an explicit confirmed reset.
- [ ] Simultaneous host/extension writes do not lose an item or resurrect cleared data.
- [ ] Revoking Full Access immediately hides cached history and blocks save/insert/mutation.

## Performance

- [ ] Release-equivalent extension `phys_footprint` ≤40 MB during sustained typing.
- [ ] Maximum history load remains ≤40 MB with no sustained growth.
- [ ] 100 appearance/dismissal cycles show no sustained growth or crash.
- [ ] p95 touch-release-to-document-proxy call ≤20 ms.
- [ ] No app-owned main-thread stall >100 ms.

Attach Instruments/trace/log locations and measurements to the release evidence. A Debug
memory label or simulator timing is diagnostic only.

## Result

Source/snapshot: __________  Device/iOS: __________  Date: __________

Owner verdict: [ ] PASS  [ ] FAIL

Open bug IDs: __________  Notes/evidence: __________
