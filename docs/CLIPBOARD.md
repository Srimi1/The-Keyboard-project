# Clipboard contract

## User promise

Clipboard history is opt-in and tap-to-save.

- Opening or foregrounding the host app does not read clipboard values.
- Showing or hiding the keyboard does not read clipboard values.
- The first save is unavailable until the local-retention notice is accepted.
- A save starts only after the user taps Apple's system Paste button.
- Automatic capture is disabled until a separate permission and password-manager device
  trial is approved.
- Clipboard text is not logged, uploaded, synced or included in backups.

Sensitive-provider markers are checked before saving, but those markers are not universal.
They are best-effort protection, never a claim that every secret can be identified.

## Retention and size limits

| Limit | Value |
|---|---:|
| Recent retention | 1 hour |
| Recent entries | 50 |
| Pinned entries | 25 |
| Stored UTF-8 bytes per item | 16 KiB |
| Encoded JSON file | 2 MiB |

Text is truncated on an extended-grapheme boundary and the UI labels a shortened item.
Whitespace-only values are rejected. Re-saving identical stored text refreshes the existing
entry and preserves its identity and pin.

Recent items expire at the one-hour boundary. Pinned items do not expire, but still obey
the item/count/file limits. Pinning item 26 is refused rather than silently evicting an
existing pinned item.

## Permission behavior

| Context | Type | View cached history | Save or mutate shared history |
|---|---:|---:|---:|
| Host app | yes | yes | yes |
| Keyboard with Full Access | yes | yes | yes |
| Keyboard without Full Access | yes | no; cached history is hidden | no |
| App Group unavailable | yes | no | no |

Typing and the next-keyboard button do not require Full Access. The extension explains the
clipboard limitation in place; it never tries to launch the containing app.

## Save pipeline

```text
user accepts notice
  → user taps PasteButton
  → system supplies NSItemProvider
  → reject known sensitive markers
  → bounded file read
  → grapheme-safe normalization and hash
  → coordinated repository transaction
  → atomic protected write
  → publish persisted receipt to UI
```

The save intent time is captured at the tap, before the provider transfer completes. A clear
operation writes a `clearedAt` fence. Any delayed save whose intent is at or before that
fence is rejected, so an asynchronous provider cannot restore cleared data.

Panel dismissal, controller deactivation and a new clear operation cancel or invalidate
provider, capture and insertion work. A confirmed pin/delete/clear is durable and may finish
after dismissal, but its receipt cannot repopulate an inactive or Full-Access-revoked UI.
Results from an older activation generation, insertion epoch or operation epoch are ignored.

## Storage and recovery

`clipboard.json` is a versioned JSON envelope stored in the App Group container. It has a
schema version, store generation, within-generation revision, clear fence and item array.
Every item is validated for:

- non-empty content;
- byte limit;
- unique UUID;
- matching SHA-256 content hash;
- section caps.

`ClipboardRepository` is asynchronous and returns typed errors. An actor serializes calls
inside one process and `NSFileCoordinator` serializes the full read-modify-write transaction
between host and extension processes.

The repository secures and backup-excludes an empty temporary file before writing clipboard
bytes, then atomically replaces the destination. Primary and backup contain the same committed
document. A commit marker binds generation, revision and content digest, so divergent or
speculative copies are not eligible for recovery. Clear, delete and expiry remove text from
both copies.

Legacy valid history is migrated on the next mutation. Confirmed structurally corrupt data
may recover from a valid backup and the damaged file is quarantined. Unsupported future
schemas and transient read failures are returned without overwriting the primary.

## UI behavior

Both host and keyboard surfaces provide:

- Save current clipboard;
- pinned and recent sections;
- pin/unpin;
- delete;
- clear all with confirmation;
- explicit busy, empty, permission, truncation and error feedback;
- VoiceOver actions for insertion, pin/unpin and delete where applicable.

Only the keyboard inserts an item into the active document. The host app is a save/history
manager and does not pretend it can paste into another app.

The controller rechecks the coordinated store and expiry immediately before insertion when
shared storage is available. This prevents a host-side clear or delete from leaving a stale
keyboard cell insertable.

## Verification boundary

Automated tests cover normalization, Unicode truncation, caps, expiry, migration, corruption,
future schemas, backup recovery, concurrent repository instances, clear-versus-capture races,
storage failures, controller cancellation and deterministic explicit-save UI behavior.

The following remain physical-device gates:

- system paste permission prompts and denial;
- Full Access revocation while the extension is visible;
- password-manager and expiring/local-only providers;
- actual host/extension process concurrency;
- extension memory under maximum clipboard load;
- reinstall retention.

Record those results in [DEVICE-ACCEPTANCE.md](DEVICE-ACCEPTANCE.md).
