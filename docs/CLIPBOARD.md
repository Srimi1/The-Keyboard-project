# CLIPBOARD.md — The clipboard manager

> **The flagship feature.** Neither Gboard-iOS nor Apple's keyboard offers clipboard history on iPhone (C-17) — iOS holds exactly one clipboard item, system-wide, forever. This is the feature that motivated the project, and the one place where it exceeds what Google ships on iOS.
>
> It is also the feature most likely to be misunderstood by a future session, because **the Android behavior cannot be fully replicated on iOS** and the reason is a platform limit, not a missing implementation. §2 is the part to read before writing any capture code.

---

## 1. Reference behavior (Gboard for Android)

What we're imitating:

- Toolbar clipboard icon opens a **panel replacing the key area**, with **Recent** and **Pinned** sections.
- **Tap an item** → inserted at the cursor.
- **Touch and hold an item** → menu with **Pin** (and delete).
- **Unpinned items auto-delete after 1 hour** — Google frames this as privacy protection. Pinned items persist indefinitely with no stated limit.
- Freshly copied content also appears as a **pill-shaped paste chip in the suggestion bar**.
- Android additionally captures **images and screenshots**; a 1h–24h retention picker appeared in a v18.0.3 beta teardown but had not shipped to stable as of the research.

`Sources:` https://support.google.com/gboard/answer/10742542 · https://www.androidauthority.com/gboard-clipboard-duration-slider-apk-teardown-3698099/

**Our v1 differences:** text only (ADR-006), fixed 1-hour retention, two-slot toolbar.

## 2. The iOS capture model — read this first

**iOS has no background clipboard monitoring for third-party apps. None. This is not a gap in an API we haven't found; it does not exist** (C-13).

Every clipboard-history app on iOS — Paste, PastePal, ClipBox — works the same way: it captures **only when its own code is running.** We have exactly three moments:

| Trigger | Runs in | Catches |
|---|---|---|
| Keyboard becomes visible | Extension | Whatever is on the pasteboard right now |
| `changeCount` poll while keyboard is visible | Extension | Copies made while typing (e.g. copy in Safari with the keyboard up) |
| Host app enters foreground | Host app | Whatever is on the pasteboard right now |

**The loss window — state this plainly to the user and never try to "fix" it:** if you copy A, then copy B, then copy C, and only *then* open the keyboard, we capture **C only**. A and B are unrecoverable — iOS overwrote them and never told anyone. The Android mental model ("everything I copy lands in history") is approximated, not reproduced.

This is [PRODUCT.md](PRODUCT.md) §7 accepted limitation #1. A session that proposes a background timer, a silent-audio keepalive, a location-based wake, or any similar trick to beat this is proposing something that either doesn't work or gets the app killed. **Don't.**

The good news: **detection is free.** `changeCount`, `hasStrings`, `hasURLs`, and `detectPatterns(for:)` do **not** trigger the paste prompt (C-16) — only reading the actual value does (C-14). So we can poll cheaply and read rarely.

## 3. Permissions & onboarding

Three steps, all required, all with live status detection in the host app ([ARCHITECTURE.md](ARCHITECTURE.md) §11):

| # | Step | Where | Why | Verify |
|---|---|---|---|---|
| 1 | Add the keyboard | Settings → General → Keyboard → Keyboards → Add New Keyboard | The keyboard can't appear otherwise | Keyboard shows in the list |
| 2 | **Allow Full Access** | Same screen → tap our keyboard → toggle on | Gates UIPasteboard, reliable App Group writes, haptics, sound (C-05, C-06) | `hasFullAccess` returns true |
| 3 | **Paste from Other Apps → Allow** | Settings → [host app] → Paste from Other Apps | Suppresses the per-read "Allow Paste" prompt; the setting on the containing app **covers its keyboard extension too** (C-15) | No prompt on capture |

**Why step 3 matters:** without it, every single capture fires a system alert (C-14) and the feature is unusable. With it, capture is silent.

⚠️ **Q-05 is unresolved:** whether "Allow" fully suppresses prompts for reads from the *extension process* on the currently installed iOS is confirmed only through Paste's iOS 17/18 docs. **M0 and M3 both verify this on device.** If prompts persist, the fallback is explicit capture — the user taps the paste chip to store an item — rather than automatic reads.

**Toggles can reset.** Reinstalls during the free account's weekly re-signing cycle (C-23, ADR-004) can clear Full Access. The onboarding screen doubles as the diagnostic so this shows up as a visible checklist item, not as "the clipboard mysteriously stopped working."

## 4. Data model & retention

Schema is in [ARCHITECTURE.md](ARCHITECTURE.md) §4. Rules:

- **Text only** in v1 (ADR-006) — URLs are stored as text. Images and screenshots are deferred behind a memory-safety spike; images in the extension process are the fastest route to a silent jetsam kill (C-10).
- **Dedupe** by `changeCount` first (cheap, prompt-free), then by content hash — copying the same string twice must not create two entries.
- **Retention:** unpinned items are swept at **1 hour** from `createdAt` (Gboard parity). Pinned items never expire.
- **Caps:** hard limits on both item size and item count, enforced at write time, chosen at M3. A pathological copy (a whole document) must be truncated, not stored whole — the memory budget is 40 MB total (C-10).
- **Sweep timing:** on keyboard appearance and on host-app foreground. No background timer exists to do it (C-13), so an item can outlive its hour on disk; it must be filtered out on read regardless.

## 5. Panel UX

Layout, cell anatomy, and required states are specified in [UI-SPEC.md](UI-SPEC.md) §8. The behaviors:

- **Tap** an item → insert at cursor via `insertText`, panel stays open (📐 verify against Gboard whether it dismisses).
- **Long-press** an item → pin / unpin / delete.
- **Sections:** Pinned first, then Recent, newest first.
- **Empty state:** explains that copied text will appear here — never a blank box.
- **No-Full-Access state:** explains *why* it's empty and links to the host app via SwiftUI `Link` (CONSTRAINTS §8 gotcha ledger — the selector-based `openURL` trick is dead on iOS 18+).
- Multi-select edit mode (the pencil in Gboard) is **v1.x**, not v1.

## 6. Paste chips

After a fresh copy is detected, a pill-shaped chip previewing the text appears in the suggestion strip ([UI-SPEC.md](UI-SPEC.md) §7).

- **Tap** → inserts the text.
- **Dismissal:** disappears once the user starts typing, or after the strip returns to candidates. 📐 MEASURE how long Gboard keeps it — this isn't documented anywhere found, so it's a screenshot/observation task.
- The chip is also the **fallback capture affordance** if Q-05 resolves badly: tapping it becomes the explicit user action that authorizes the read.

## 7. Privacy stance

- **100% local.** Everything lives in the App Group container on device.
- **No network path exists in the extension** — not sync, not analytics, not crash reporting (ADR-005). Full Access unlocks network; we never use it. This is the whole reason a keyboard with clipboard access is trustworthy.
- **Sensitive content:** password managers can mark pasteboard items as local-only or expiring. Whether those hints reach the extension and whether our capture respects them is **Q-09 — unverified.** Verify at M3 and, if the hints are visible, honor them by skipping capture.
- No item is ever transmitted, logged off-device, or shared between users. There are no other users (PRODUCT.md §6).

## 8. Edge cases

| Case | Required behavior |
|---|---|
| Very large string copied | Truncate to the size cap before storing; never store unbounded (C-10) |
| Rapid successive copies | `changeCount` dedupe; store the latest, don't thrash the store |
| Identical content re-copied | Content-hash dedupe; do not duplicate the entry |
| Pasteboard cleared by system | No capture, no error; existing history unaffected |
| Full Access revoked mid-life | Existing items remain readable (reads work without it, C-12); capture stops; panel shows the no-access state |
| App Group unavailable | Keyboard still types; clipboard degrades to empty ([ARCHITECTURE.md](ARCHITECTURE.md) §9) |
| Item expires while panel is open | Filter on read; don't show an expired item that a later refresh would remove |
| Copy happens in a secure field's app | Nothing special — we capture text, not context |

## 9. Acceptance tests (M3 exit criteria)

All run on a real device, with onboarding complete. **M3 does not close until every one passes.**

| # | Test | Pass condition |
|---|---|---|
| **A-01** | Copy text in Safari → open keyboard in Notes | Item appears in Recent, **no paste prompt** |
| **A-02** | Tap the item in the panel | Text inserts at the cursor |
| **A-03** | Copy with the keyboard already visible | Item appears via `changeCount` polling, no prompt |
| **A-04** | Long-press an item → Pin | Moves to Pinned, survives app restarts |
| **A-05** | Wait > 1 hour with an unpinned item | Item is gone; pinned items remain |
| **A-06** | Copy the same string twice | Exactly one entry |
| **A-07** | Copy a very large text block | Stored truncated; memory stays ≤ 40 MB |
| **A-08** | Toggle Full Access off → open panel | No-access state with a working link to the host app; **keyboard still types** |
| **A-09** | Fresh copy → check the suggestion strip | Paste chip appears; tapping inserts |
| **A-10** | Copy → open host app | Item captured on foreground; history viewer shows it |
| **A-11** | Instruments during heavy panel use | `phys_footprint` ≤ 40 MB (C-10) |
| **A-12** | Copy from a password manager | Q-09 resolved and recorded in CONSTRAINTS.md; behavior matches whatever the answer requires |

---

*Related docs: [PRODUCT.md](PRODUCT.md) (why this feature is the flagship, and its accepted limits) · [UI-SPEC.md](UI-SPEC.md) §7–8 (panel and chip visuals) · [ARCHITECTURE.md](ARCHITECTURE.md) §4–5 (store schema and capture pipeline) · [CONSTRAINTS.md](CONSTRAINTS.md) §5 (the pasteboard rulebook) · [ROADMAP.md](ROADMAP.md) M3.*
