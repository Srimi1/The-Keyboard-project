# Product scope

## Problem

The owner moved from Android to iPhone and wants Gboard-Android's familiar typing geometry,
long-press behavior and multi-item clipboard workflow without sending typed or copied content
to a service.

## v1 promise

The first public version is deliberately focused:

- iPhone-only, English (US), iOS 16 minimum subject to compatibility verification;
- reliable tap typing, shift/caps, symbols, return variants and hold-to-delete;
- long-press accents/punctuation and spacebar cursor movement;
- a real next-keyboard control and usable VoiceOver actions;
- persistent haptic, sound and system/light/dark preferences;
- explicit tap-to-save text history with paste, pin/unpin, delete, clear and expiry;
- offline operation with no accounts, analytics, ads or app-owned networking;
- useful setup, settings and history management in the host app.

Typing and next-keyboard switching work without Full Access. Shared history does not: when
Full Access is unavailable the keyboard hides its cache rather than risk showing or inserting
an item that the host may already have deleted.

## Clipboard promise

The product never watches the clipboard. Opening or foregrounding the app, showing the
keyboard and changing panels do not read clipboard values. The system supplies a value only
after the user accepts the retention notice and taps `PasteButton`.

Recent text lasts one hour unless pinned. Limits are 50 recent items, 25 pinned items, 16 KiB
per item and a 2 MiB encoded store. Storage stays local and backup-excluded. Sensitive-content
markers reduce risk but are not a password detector or guarantee.

## Reference and acceptance

Android Gboard screenshots and the owner's typing feedback are the layout reference. A Debug
host preview supports deterministic regression tests, but only the installed extension can
approve globe behavior, document-proxy editing, haptics, permissions, memory and typing feel.

The first-iPhone delivery is accepted only after a full day in Notes, Messages drafts and
Safari without switching because of a keyboard defect. Public v1 additionally requires the
14-day TestFlight and release gates in [ROADMAP.md](ROADMAP.md).

## Deferred

- Suggestions and autocorrect: first post-v1 typing update.
- Automatic clipboard capture: unavailable until separate permission/password-manager trials
  and a new privacy decision approve it.
- Glide typing, gesture word delete, emoji search, multiple languages, image clipboard,
  accounts, sync and cloud features.

Deferred behavior must not appear in v1 copy or be represented as partially supported.

## Known platform limits

- iOS may replace a custom keyboard in secure/password and phone-pad fields, and an app may ban
  third-party keyboards.
- There is no supported background clipboard monitoring, so manual history contains only items
  the user explicitly saves.
- A custom keyboard cannot use Apple's private autocorrect engine.
- Development provisioning expires; a free Personal Team generally requires reinstalling after
  seven days. TestFlight/App Store distribution requires the paid program.
