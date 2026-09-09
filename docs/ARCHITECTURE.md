# Architecture

## Product boundary

The project has two iPhone targets:

```text
Host app                         Keyboard extension
----------------------------     --------------------------------
onboarding                       UIInputViewController
settings and history             native key rendering
Debug-only keyboard preview      UIKit multi-touch capture
                                 inline settings and clipboard
             \                   /
              App Group container
              versioned JSON + shared defaults
```

Both targets compile the small types under `Sources/Shared`; there is no shared framework
and no third-party runtime dependency. The host app embeds the extension. The extension
bundle identifier is a child of the host identifier and both signed targets must contain
`group.com.srijan.keyboardproject`.

The extension is treated as a constrained, disposable process. Typing cannot depend on the
App Group, Full Access, clipboard availability or the host app.

## Typing

`KeyboardViewController` owns `textDocumentProxy` and conforms to
`KeyboardActionHandler`. SwiftUI receives only this narrow interface:

```text
UIKit touches → KeyboardTouch[] → KeyboardViewModel → KeyboardActionHandler
                                               ├── insert
                                               ├── delete
                                               ├── cursor movement
                                               └── next-keyboard UIKit button
```

`MultiTouchView` is a transparent UIKit surface with `isMultipleTouchEnabled = true`.
It orders a batch by touch timestamp and assigns stable identities. Physical key IDs do not
change when shift changes the displayed letter, so a layout rerender cannot lose a held
finger. A new press commits earlier held keys in press order.

Each active finger owns its long-press task and cursor-slide state. Dismissal, rotation,
layer changes and panel changes cancel touches, repeat timers, callouts and pending
gestures. The real globe control is a UIKit button so the system can show its input-mode
menu.

Custom `UIAccessibilityElement` objects expose every non-globe key with a real activation
action; the system button supplies globe-key accessibility.

## Clipboard contract

Clipboard access is manual-first. Neither target reads `UIPasteboard` during launch,
foregrounding or keyboard appearance. The user taps a SwiftUI `PasteButton`, and its
`NSItemProvider` is read through a bounded file representation.

`ClipboardController` is a main-actor presentation layer. It owns consent/permission
state, visible history, notices and cancellable operations. It never publishes optimistic
history: UI state comes from a persisted repository receipt.

`ClipboardRepository` is an actor. Its public methods are asynchronous and return typed
snapshots or mutation receipts. Inside a process the actor orders work; between the host
and extension an `NSFileCoordinator` claim covers the complete read-modify-write
transaction.

The JSON envelope contains:

- `schemaVersion` for compatible migration and future-schema rejection;
- a store `generation` plus a revision monotonic within that generation for stale-result
  rejection and destructive-reset detection;
- `clearedAt` as a durable fence against delayed captures;
- validated `ClipboardItem` values and content hashes.

Writes secure and backup-exclude an empty temporary inode before adding bytes, then atomically
replace the destination. Primary and recovery copies mirror the same committed document; a
marker binds generation, revision and content digest so deleted or expired text cannot be
resurrected from divergent data. Existing artifacts and quarantines are migrated to the same
metadata policy before decoding. A confirmed corrupt primary may recover from the last good
copy; transient I/O errors and future schemas do not. Unreadable data is preserved rather than
silently replaced by empty history.

See [CLIPBOARD.md](CLIPBOARD.md) for limits and permission behavior.

## Settings

`KeyboardSettingsStore` persists one versioned, timestamped settings record:

- haptics;
- keypress sound;
- System/Light/Black/Neon appearance, rendered from one shared set of native surface tokens;
- clipboard mode;
- clipboard notice version.

The whole newer record wins, and stores refresh immediately before each field edit. When
shared defaults are reachable, the selected record is reconciled into both shared and
process-local defaults. This keeps basic preferences
available after Full Access is revoked. Defaults are haptics on, sound off, system
appearance and manual clipboard mode gated by the retention notice.

Automatic clipboard capture cannot currently be enabled, including from a stale stored
value.

## Failure and privacy boundaries

| Condition | Typing | Clipboard behavior | Settings |
|---|---|---|---|
| Full Access off | available | cached history hidden; extension cannot save/insert/mutate | local mirror |
| App Group unavailable | available | typed error and unavailable UI | local mirror |
| Corrupt JSON | available | preserve data, recover only from valid backup | unaffected |
| Extension dismissal/rotation | pending input cancelled | transient work invalidated; confirmed mutations finish without stale UI | persisted |
| Secure or restricted field | iOS may replace the custom keyboard | unavailable | unchanged |

There is no app-owned networking, analytics, advertising or account system. Full Access
technically grants broader extension capability, which is why code and static checks—not
the permission name—enforce the offline product policy. Clipboard text is never logged.
Stored files use complete data protection and backup exclusion.

## Debug and Release separation

The keyboard preview, pasteboard diagnostic probe and live memory diagnostics compile only
under `DEBUG`. Release builds keep the normal clipboard/settings toolbar but none of those
harnesses. CI compiles an unsigned iPhone-architecture Release build; public distribution still
requires a signed Organizer archive and its own evidence.

## Deferred architecture

Suggestions, autocorrect, personal dictionaries, automatic capture and cloud features are
not part of v1. They must not be presented as implemented and must pass a separate privacy,
memory and device-design review before entering the runtime.
