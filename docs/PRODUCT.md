# PRODUCT.md — What we're building and why

> **This is the scope authority.** If a feature isn't in the v1 list below, it isn't in v1 — regardless of how easy it looks mid-session. Adding to v1 requires an ADR in [DECISIONS.md](DECISIONS.md).

---

## 1. Vision

**A keyboard that makes an iPhone feel like it has Gboard on it.**

The owner switched from Android to iPhone and lost two things: the *layout* (key positions, the bottom row, long-press behavior — muscle memory that misfires dozens of times a day) and the *clipboard manager* (Gboard-Android keeps a history of what you copied; iOS keeps exactly one item, forever, with no history at all).

**Success criterion — one sentence:** *"I use this keyboard all day, by choice, and never switch back to the stock one for ordinary typing."*

That's the bar. Not "it works." Not "it's impressive for a personal project." Daily-drivable, or it failed.

Three sub-criteria make that testable:
- **Muscle memory transfers.** An Android-Gboard user types on it without hitting the wrong key or long-pressing for a symbol that isn't there.
- **The clipboard is genuinely useful.** Copy something, open the keyboard somewhere else, paste it — including the thing you copied three copies ago.
- **It never disappears.** No jetsam kills mid-sentence, no silent failures (C-03, C-10).

## 2. Reference products

| Product | Role here |
|---|---|
| **Gboard for Android** | **The blueprint.** Every layout and interaction question resolves to "what does Gboard-Android do" (ADR-001). Pin a version and capture reference screenshots at M0. |
| **Gboard for iOS** | **A cautionary baseline.** Frozen at **v2.3.19 (May 2, 2022)** and still shipping — Google stopped developing it. It has glide typing, spacebar cursor slide, voice, translate, themes. It has **no clipboard manager**, no number row, no toolbar customization, no gesture delete (C-17). |
| **Apple stock iOS keyboard** | **The thing being replaced**, and the source of iOS conventions we must respect (globe-key handling, C-21). Never a design target. |

The headline: **the flagship feature of this project — clipboard history — is something neither Google nor Apple ships on iOS.** This isn't a worse copy of Gboard-iOS. On the feature that motivated the project, it exceeds it.

## 3. Parity matrix

`✅` = has it · `❌` = doesn't · `v1` / `v2` / `later` = our target · `never` = explicit non-goal

| Feature | Gboard Android | Gboard iOS | Apple stock | **This project** |
|---|:--:|:--:|:--:|:--:|
| **Layout & typing** ||||
| Android 4-row QWERTY geometry | ✅ | partial | ❌ | **v1** |
| Bottom row `[?123][,][space][.][return]` | ✅ | partial (has period) | ❌ | **v1** |
| Shift tap / double-tap caps lock | ✅ | ✅ | ✅ | **v1** |
| Symbols layers (`?123`, `=\<`) | ✅ | ✅ | ✅ | **v1** |
| Long-press accents on letters | ✅ | ✅ | ✅ | **v1** |
| Long-press digit hints (q–p → 1–0) | ✅ | hints toggle | ❌ | **v1** |
| Long-press period → punctuation grid | ✅ | partial | ❌ | **v1** |
| Long-press comma → settings popup | ✅ | ❌ | ❌ | **v1** |
| Enlarged key-preview popup on press | ✅ | ✅ | ✅ (letters) | **v1** |
| Backspace hold-repeat + acceleration | ✅ | ✅ | ✅ | **v1** |
| Double-space → period | ✅ | ✅ | ✅ | **v1** |
| Spacebar slide → cursor control | ✅ | ✅ (L/R) | ✅ (trackpad) | **v1** |
| Auto-capitalization | ✅ | ✅ | ✅ | **v1** |
| Dedicated number row | ✅ (opt-in) | ❌ | ❌ | later |
| Glide / swipe typing | ✅ | ✅ | ❌ | **v2** |
| Gesture delete (backspace slide) | ✅ | ❌ | ❌ | later |
| **Clipboard** ||||
| Clipboard history panel | ✅ | ❌ | ❌ | **v1** ⭐ |
| Pin items indefinitely | ✅ | ❌ | ❌ | **v1** |
| 1-hour auto-expiry for unpinned | ✅ | ❌ | ❌ | **v1** |
| Paste chip in suggestion bar | ✅ | ❌ | ❌ | **v1** |
| Image / screenshot capture | ✅ | ❌ | ❌ | later |
| **Suggestions** ||||
| 3-candidate suggestion strip | ✅ | ✅ | ✅ | **v1** |
| Autocorrect on space | ✅ | ✅ | ✅ | **v1** (weaker — §6) |
| Personal dictionary learning | ✅ | ❌ (no sync) | ✅ | **v1** |
| Next-word prediction | ✅ | ✅ | ✅ | later |
| **Chrome & extras** ||||
| Toolbar in idle strip | ✅ (6 custom slots) | partial | ❌ | **v1** (2 fixed slots) |
| Light + dark theme | ✅ | ✅ | ✅ | **v1** |
| Haptics + key click sound | ✅ | ✅ | ✅ | **v1** (needs Full Access, C-07) |
| Themes engine / photo themes | ✅ | ✅ | ❌ | never |
| Emoji keyboard + search | ✅ | ✅ | ✅ | later (system emoji is one tap away) |
| One-handed / floating / resize | ✅ | partial | ❌ | later |
| Voice typing | ✅ | ✅ | ✅ | **never** (network) |
| Translate / GIF / Google search | ✅ | ✅ | ❌ | **never** (network) |
| Multilingual | ✅ | ✅ | ✅ | **never** in v1 (ADR-002) |

## 4. v1 scope — the authoritative list

Detailed geometry and interaction specs live in [UI-SPEC.md](UI-SPEC.md); the clipboard has its own spec in [CLIPBOARD.md](CLIPBOARD.md).

**Layout & typing**
1. Gboard 4-row QWERTY: 10-key top row, 9-key home row centered with a half-key inset, `shift + zxcvbnm + backspace` with shift/backspace at ~1.5× letter width.
2. Bottom row: `[?123 15%] [, 10%] [space ~50%, labeled "English (US)"] [. 10%] [return ~15%]`.
3. Layers: base, shifted, caps-lock, `?123` symbols, `=\<` extended symbols.
4. Shift state machine: tap = next letter only, double-tap = caps lock, plus auto-capitalization at sentence starts.
5. Long-press system: accent callouts on letters, digit hints 1–0 on q–p, period → punctuation grid (~14 symbols), comma → mini-popup with settings gear; corner hint glyphs rendered on keys.
6. Enlarged key-preview popup on keypress, with slide-off cancellation.
7. Backspace hold-repeat with acceleration.
8. Double-space → period + space; spacebar slide → cursor left/right via `adjustTextPosition` (C-18).
9. Globe key shown **only** when `needsInputModeSwitchKey` is true, wired to `handleInputModeList` (C-21).

**Clipboard manager** ⭐ *the reason this project exists*

10. Opportunistic capture — pasteboard read on keyboard open, `changeCount` polling while visible, capture on host-app foreground (C-13, C-16).
11. Panel replacing the key area: **Recent** + **Pinned** sections, tap to insert at cursor, long-press to pin/delete.
12. Unpinned items auto-expire after **1 hour** (Gboard parity); pinned persist indefinitely.
13. Pill-shaped paste chip in the suggestion bar after a fresh copy.
14. **Text only** in v1 (ADR-006). All data local in the App Group container; **no network path exists** (ADR-005).

**Suggestions & correction**

15. Suggestion strip: 3 candidates, middle slot = the autocorrect choice applied on space, literal typed string always reachable.
16. Engine: `UITextChecker` + `UILexicon` via `requestSupplementaryLexicon` + bundled frequency dictionary (ADR-009).
17. Backspace immediately after a correction reverts it.
18. Personal dictionary learning into the App Group store.

**Chrome**

19. Idle-strip toolbar with **two fixed slots** in v1: clipboard, settings.
20. Haptic feedback + key click sound, both gated on `hasFullAccess` with silent degradation (C-07, C-08).
21. Gboard light + dark themes with key-border toggle; **transparent background** for iOS 26 Liquid Glass (CONSTRAINTS §8 gotcha ledger).
22. Keyboard height tuned per device class, handling the known initial-height flicker (C-22).

**Host app**

23. Onboarding checklist with live status: add keyboard → enable Full Access → set "Paste from Other Apps" = Allow.
24. Settings screen.
25. Full clipboard history viewer/manager.
26. App Group shared storage for clipboard + settings, with settings mirrored to local defaults using timestamp conflict resolution (C-12).

## 5. Deferred — with the reason each was cut

Deferred means **"not now, and here's why"** — not "forgotten." Promoting anything here into scope requires an ADR.

| Feature | Target | Why deferred |
|---|---|---|
| **Glide typing** | v2 | The hardest feature in scope. No open-source iOS implementation exists; KeyboardKit ships it in neither tier; the only credible open path is FUTO Swipe's GPL C++ library, never ported to iOS. M6 runs the port spike (ADR-007). |
| **Emoji keyboard + search** | later | Pro-gated in KeyboardKit; iOS 18/Xcode 16 broke multi-gesture buttons in scrollable grids (known rewrite pain); the system emoji keyboard is one globe-tap away. |
| **Image / screenshot clipboard** | later | Images in the extension process are the fastest route to a silent jetsam kill under the ~60 MB ceiling (ADR-006). |
| **Dedicated number row** | v1.x | Off by default on Gboard-Android anyway; long-press digit hints cover it; trivial to add once the layout engine is proven. |
| **Gesture delete** | later | Needs the same continuous-gesture engine as glide typing; ships with it or not at all. |
| **Themes engine / photo themes** | never (v1 scope) | One faithful light/dark pair serves a single user. A themes engine is Pro-gated and pure scope creep. |
| **One-handed / floating / resize tool** | later | Polish. Height tuning in v1 covers the ergonomic need. |
| **Next-word prediction** | later | Wait until correction itself feels safe (ADR-009). Prediction on top of shaky correction compounds errors. |

## 6. Non-goals

These are **not deferred — they are rejected.** Do not propose them.

- **Any networked feature** — voice typing, translate, GIF search, Google search, sync, analytics, crash reporting. Full Access unlocks network; we never use it (ADR-005). This is the privacy stance and it is not negotiable.
- **Multilingual support** — English only (ADR-002).
- **App Store distribution** — personal sideload / TestFlight only (ADR-004). Guidelines are recorded in C-30 purely so a future decision isn't made blind.
- **Other users** — no accounts, no sharing, no multi-device. One person, one phone.
- **Being a better Gboard** — the goal is *feeling like Gboard*, not improving on it. Ideas that are "better than Android" but break muscle memory lose by default.

## 7. Accepted limitations

**These are platform truths, not bugs. Do not try to fix them, and do not let a session invent an API to work around them.**

1. **Clipboard capture has loss windows.** iOS has zero background clipboard monitoring (C-13). We capture when the keyboard opens, while it's visible, and when the host app foregrounds. Anything copied between those moments — beyond the single most recent item — is gone. The Android mental model ("everything I copy is in history") is **not fully replicable on iOS**. Every clipboard-history app on the platform has this limitation.
2. **Autocorrect will be worse than Gboard.** Apple exposes no system autocorrect engine to extensions (C-19). The bar is "good enough that I don't disable it," not "matches Google's ML stack" (ADR-009).
3. **The keyboard sometimes just isn't available.** iOS forces the system keyboard in password (`secureTextEntry`) and phone-pad fields, and any app can ban third-party keyboards outright — banking apps commonly do (C-20). Keep the system keyboard enabled as fallback.
4. **We can't see the whole text field.** `documentContextBeforeInput` returns roughly the last couple of sentences, never the full document (C-18). Auto-caps and correction must work inside that window.
5. **No haptics or sound without Full Access** — the APIs silently no-op (C-07). The keyboard still types; the feel degrades.
6. **The keyboard dies weekly while on the free developer account** — 7-day provisioning expiry (C-23). Structural fix is the $99 upgrade at M5 (ADR-004).
7. **The keyboard can vanish under memory pressure.** Jetsam kills at ~60 MB with no crash log (C-10). Mitigated by the ≤40 MB budget, never eliminated.

---

*Related docs: [UI-SPEC.md](UI-SPEC.md) (how v1 looks and behaves) · [CLIPBOARD.md](CLIPBOARD.md) (the flagship feature in detail) · [CONSTRAINTS.md](CONSTRAINTS.md) (the platform facts behind §7) · [DECISIONS.md](DECISIONS.md) (why scope is drawn here) · [ROADMAP.md](ROADMAP.md) (the order it gets built).*
