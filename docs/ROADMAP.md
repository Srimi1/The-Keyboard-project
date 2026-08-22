# ROADMAP.md — From empty folder to daily driver

> The work queue. Each milestone has **items** and **exit criteria** — a milestone isn't done because the items are checked off, it's done when the exit criteria are demonstrably met on a real device.
>
> **Every milestone exits with two universal gates:** (1) an on-device typing test, and (2) an Instruments `phys_footprint` measurement ≤ **40 MB** (C-10). No exceptions — a keyboard that vanishes mid-sentence is the worst failure this project can ship.

---

## Status

| Milestone | Goal | Status |
|---|---|---|
| M0 | Foundations & feasibility spike | code done, 3 device tests open |
| M1 | Typeable Gboard QWERTY | code done, device verification open |
| M2 | Gboard feel — long-press, gestures, feedback | **← current** |
| M3 | Clipboard manager | not started |
| M4 | Suggestions & autocorrect | not started |
| M5 | Daily-driver hardening + paid account | not started |
| M6 | v2 exploration (optional) | not started |

**Docs phase:** complete (2026-08-21). This doc set exists; M0 begins after review.

---

## M0 — Foundations & feasibility spike

**Goal: kill the unknowns before writing product code.** Three research questions could each invalidate a chunk of the plan; find out now, not in month two. ~1 week.

**Items**

1. ✅ **Done 2026-08-21.** Xcode project created via XcodeGen (`project.yml`): `KeyboardProject` host app + `KeyboardExtension`, bundle IDs `com.srijan.keyboardproject{,.keyboard}` (ADR-008), `RequestsOpenAccess = true` (C-06), App Group `group.com.srijan.keyboardproject` on both targets. Builds clean for the simulator with signing disabled; extension verified embedded in `PlugIns/` with the correct `NSExtension` dictionary. Ships a dependency-free keyboard (Gboard row structure + AOSP bottom-row widths) and an in-keyboard diagnostics panel that runs the tests below.
2. ✅ **Done 2026-08-21.** Deployed to an iPhone 14 (iOS 26.5) on the free personal team.
3. ✅ **Done 2026-08-21 — PASSED.** **EMPIRICAL TEST 1 — App Groups on a free team (Q-01).** Keyboard's Diagnostics panel showed the extension's App Group write succeeding; the host app read the report back. Recorded in CONSTRAINTS.md, C-25's verified flag flipped. The free personal team is sufficient — **no need to buy the $99 program early** (ADR-004's trigger condition didn't fire); it stays deferred to M5.
4. **🔬 EMPIRICAL TEST 2 — KeyboardKit 10 free-tier spike (ADR-003, Q-02).** Record the dependency-free keyboard's `phys_footprint` first (the panel shows it live) — that is the baseline. Then add KeyboardKit in a separate commit, express the Gboard bottom row `[?123][,][space][.][return]` and ~1.5× shift/backspace in its free layout engine, run **in Airplane Mode** to confirm no license/network validation misbehaves inside the extension, and compare the memory delta. Keeping it a separate commit means a failed spike backs out cleanly.
5. **🔬 EMPIRICAL TEST 3 — pasteboard behavior (Q-05).** With Full Access on, tap **Read pasteboard value** in the keyboard's diagnostics panel. The panel reports `changeCount`, `hasStrings`, whether a value came back, and the read duration — a fast read means no prompt, a multi-second read means the prompt appeared, which is the only signal iOS gives. Verify "Paste from Other Apps = Allow" suppresses it (C-15) and that the prompt-free probes never trigger an alert (C-16).
6. Close **ADR-003** (KeyboardKit 10 free tier vs. the MIT 9.9.0 fork) and pin the exact version.
7. **📸 Capture Gboard-Android reference screenshots** — the full V-01…V-11 list in [UI-SPEC.md](UI-SPEC.md) §12. Every 📐 MEASURE item is blocked until these exist.
8. Fold all M0 findings into CONSTRAINTS.md with sources, dates, and verified flags.

**Exit criteria**
- ✅ You typed "hello" into Notes from your own keyboard extension on your own iPhone.
- ✅ Q-01, Q-02, Q-05 have recorded verdicts in CONSTRAINTS.md.
- ✅ ADR-003 is closed (Accepted or superseded), version pinned.
- ✅ Reference screenshots captured and stored in `docs/reference/`.

---

## M1 — Typeable Gboard QWERTY

**Goal: a keyboard you can actually write messages with**, laid out like Android.

**Items**
- ✅ 4-row layout per [UI-SPEC.md](UI-SPEC.md) §1: 10/9/7 letter rows, centered home row, 15% shift/backspace, AOSP bottom-row widths, spacebar labeled "English (US)".
- ✅ Layers: base, shifted, caps-lock, `?123`, `=\<` with correct layer-switch keys (§2). *Layer contents are still placeholders — blocked on V-03.*
- ✅ Shift state machine: tap, double-tap caps lock, auto-capitalization honoring the field's `autocapitalizationType` (C-18).
- ✅ Backspace hold-repeat; return-key labels from `returnKeyType`. Held backspace accelerates to two characters per tick after 20 deletes — AOSP never escalates to word deletion, and Gboard's word delete is the slide-left gesture deferred with ADR-007.
- ✅ Globe key conditional on `needsInputModeSwitchKey`, as a real UIButton on `.allTouchEvents` (C-21, C-47).
- ✅ Key-preview popup on press; slide-off cancellation with hysteresis (§3–4).
- ✅ **Multi-touch rollover** via a UIKit touch layer — SwiftUI gestures cannot express it (§3).
- ✅ Light + dark palettes (§9) with a **transparent** keyboard background (CONSTRAINTS §8 gotcha ledger).
- ✅ Keyboard height derived from key width so proportions hold across device classes; constraint at priority 999, re-applied on layout and rotation (C-22, C-45).
- ✅ Timings in `KeyboardTimings.swift` replaced with AOSP constants, each citing its source file.
- ⬜ Resolve the 📐 MEASURE geometry from reference screenshots (V-01, V-02, V-03, V-08, V-11).

**Verification so far:** **52 unit tests + 19 UI trials, all passing** (re-run 2026-08-22).

- *Unit* — the typing rules and layout maths: AutoCapitalization 15, KeyboardLayout 8,
  KeyboardMetrics 12, MoreKeys 9, ReturnKeyLabel 1, ShiftController 7.
- *UI trials* (`UITests/`) — the touch layer, which the unit tests cannot reach. Keys are
  drawn rects under a raw `MultiTouchView`, so hit-testing, rollover, press-vs-release and
  hold-to-repeat only exist once real touches land on real coordinates: BackspaceRepeatProbe 1,
  BackspaceTrials 4, CalibrationProbe 2, LayerTrials 3, MultiTouchProbe 2, TypingTrials 7.
  They drive the **host app**, which compiles `Sources/Keyboard` in — so they exercise the real
  keyboard code but never the extension process (no proxy, no Full Access, no globe key, no
  jetsam limit). Those stay device-only.

The
host app carries a **Keyboard preview** screen rendering the real `KeyboardRootView`, so the
side-by-side comparison below can be done without switching keyboards
(`xcrun simctl launch <device> com.srijan.keyboardproject -keyboardPreview` scripts the capture).

**Exit criteria**
- ⬜ A full day of plain typing in Messages/Notes/Safari without switching to the stock keyboard. *(needs a device)*
- ⬜ Side-by-side against reference screenshots: no obvious geometry deltas. *(blocked on the M0 screenshots)*
- ⬜ ≤ 40 MB. *(the keyboard reports its own footprint live in the diagnostics bar)*

---

## M2 — Gboard feel: long-press, gestures, feedback

**Goal: muscle memory transfers.** This is the milestone that decides whether it *feels* like Android or merely *looks* like it.

**Items**
- ✅ Long-press callouts ([UI-SPEC.md](UI-SPEC.md) §5): accents, top-row digit hints as the leading option, period → punctuation grid. Slide to choose, release to insert.
- ⬜ Comma → settings-gear popup. **Deliberately not built**: reaching the host app needs SwiftUI `Link` (C-48), which a UIKit-driven callout cannot host. Needs a different approach, not a missing implementation.
- ✅ Double-space → period on the sourced 1100 ms window; immediate backspace restores the two spaces.
- ✅ Spacebar slide cursor control via `adjustTextPosition` (§6). Step distance is still 📐 MEASURE.
- ✅ Haptics + key click, gated on `hasFullAccess` with silent degradation (C-07, C-08). Click audibility is **Q-03, unverified**.
- ✅ Replaced the working accent sets and punctuation grid with AOSP's sourced `donottranslate-more-keys.xml` values (2026-08-21) — contents and order verified against the primary source exactly; see [UI-SPEC.md](UI-SPEC.md) §5a/§5c.
- ✅ **Release trim (2026-08-22).** The M0 harness was never gated out of Release: every
  keyboard appearance, in every app, ran a UUID file write + read-back + delete in the shared
  container, a pasteboard IPC probe, a JSON encode and a second verified write — plus a 1 Hz
  `Timer` for as long as the keyboard was visible. Worse, the memory figure it computed was
  never displayed: `diagnostics` is a nested `ObservableObject` that does not forward
  `objectWillChange`, so the timer's only effect was main-thread work. `DiagnosticsRunner` and
  `DiagnosticsPanel` now compile out of Release entirely (0 symbols in the shipped `.appex`,
  verified with `nm`); the Debug readout was fixed to actually update. What ships instead is
  `KeyboardHandshake` — one small record, written off the main thread and only when it changed
  or went stale, which is all the host app's checklist needs.
- ✅ **The `"M1"` label and live MB readout are gone from Release** (they were an M5 blocker).
  The strip keeps its height as reserved space for M4's suggestion bar, so Debug and Release
  keyboards stay the same shape and today's geometry measurements remain valid.
- ⬜ **Q-10 — the globe key.** `needsInputModeSwitchKey` is currently trusted to decide whether
  a globe key is drawn at all (C-21, unverified). If it returns false where no system globe
  exists, the user is stranded on this keyboard — and failing to provide a next-keyboard method
  is a confirmed App Review rejection (C-30, 4.4.1). Debug builds now show the live value in the
  strip; read it on device and record the verdict before changing behavior.
- ⬜ Resolve the remaining 📐 MEASURE items from reference screenshots — especially **V-06, the period grid's contents and ordering**.
- ⬜ Side-by-side screenshot comparison; fix every visible delta.

**Exit criteria**
- ⬜ You (the Android Gboard user) report **no muscle-memory misses** on layout or long-press over a full day. *(needs a device)*
- ⬜ All V-01…V-08 measurements resolved and reflected in UI-SPEC.md. *(blocked on the M0 screenshots)*
- ⬜ ≤ 40 MB.

---

## M3 — Clipboard manager ⭐

**Goal: the flagship feature works end-to-end.** This is the reason the project exists.

**Items** — in build order, which is also value order:

1. App Group clipboard store: schema, file-backed persistence, dedupe (changeCount + content hash), size/count caps ([ARCHITECTURE.md](ARCHITECTURE.md) §4).
2. Capture pipeline: read on keyboard appear, `changeCount` poll while visible, capture on host-app foreground (§5). Resolve **Q-09** (password-manager pasteboard hints) *before* this ships — capturing a copied password would be the single worst bug this project could have.
3. **Paste chip** in the strip after a fresh copy. Build this before the panel: it covers the common case (paste the thing you just copied) in one tap and without opening anything, which is most of the daily value. It is also the first real content the reserved strip carries.
4. Panel UI: Recent + Pinned replacing the **key area only** — the strip stays visible — with tap-to-insert, long-press pin/delete, and honest empty and no-Full-Access states ([UI-SPEC.md](UI-SPEC.md) §8).
5. Retention: 1-hour sweep for unpinned; pinned persist.
6. Host app: full clipboard history viewer/manager. The onboarding flow it used to be paired with already exists as of 2026-08-22.

**Enhancement notes** (what makes this feel like Gboard rather than a list view):
- The panel replaces the keys, never the whole keyboard — losing the strip mid-task is disorienting and is not what Gboard does.
- Pin is the feature that turns a history into a tool. It needs to be reachable in one gesture from the panel, not behind the host app.
- Every state needs copy that says what to do: empty, Full Access off, and "nothing captured because you have not copied anything yet" are three different situations and must not share a message.

**Exit criteria**
- ✅ **All 12 acceptance tests in [CLIPBOARD.md](CLIPBOARD.md) §9 pass on device**, with zero paste prompts after onboarding.
- ✅ ≤ 40 MB during heavy panel use.

---

## M4 — Suggestions & autocorrect

**Goal: the strip earns its screen space.**

**Items**
- Strip UI: 3 candidate slots, middle = autocorrect, literal always reachable; idle state = toolbar with clipboard + settings slots ([UI-SPEC.md](UI-SPEC.md) §7).
- Candidate engine: `UITextChecker` guesses/completions + `UILexicon` via `requestSupplementaryLexicon` + memory-mapped frequency dictionary for ranking (C-19, ADR-009).
- Autocorrect-on-space with **conservative** thresholds; backspace-after-correction reverts.
- Personal dictionary learning into the App Group store; visible in the host app.
- Tune against a week of real typing; keep a misfire log and adjust thresholds from it.

**Exit criteria**
- ✅ A full day of typing without wanting to disable autocorrect.
- ✅ Misfire log shows the failure direction is **under**-correcting, not word-destroying over-correction.
- ✅ ≤ 40 MB with the dictionary loaded.

---

## M5 — Daily-driver hardening + paid account

**Goal: this is now your keyboard.**

**Items**
- **Buy the $99 Apple Developer Program** (ADR-004), enrolled as the App Store Connect account (ADR-010). Move to 1-year development signing or TestFlight internal builds (90-day OTA, C-27). Retire the weekly re-sign ritual.
- Memory audit with Instruments across heavy usage: long sessions, panel open/close cycles, many different host apps. Fix the `UIInputViewController` retention leaks (C-02). Verify on the oldest device in use.
- Edge-case sweep: secure/phone-pad fallback (C-20), apps that ban third-party keyboards, orientation changes, Full Access toggled off mid-session, empty/cleared pasteboard.
- iOS-version check on the current release: Liquid Glass background, height behavior, gesture handling. Update the C-26 gotcha ledger with anything new.
- Set as **default keyboard**; 2-week burn-in with an issue log; fix everything that made you switch back.
- **App-Store-readiness checklist (ADR-010)**:
  - ✅ **Done 2026-08-21.** `PrivacyInfo.xcprivacy` shipped in both targets, declaring no tracking, no collected data, and `NSPrivacyAccessedAPICategoryUserDefaults` / `1C8F.1` (C-31, C-32). Bundled and lint-verified; **not yet validated by a real App Store Connect upload** — do that as soon as the paid account exists.
  - ⬜ Write and host a privacy-policy page; link it from the host app **and** the App Store Connect listing (C-30, guideline 5.1.1). Still the largest open submission blocker.
  - ⬜ Re-confirm C-30's 4.4 / 4.4.1 / 5.1.2 items against the actual shipping build (they hold as of 2026-08-21 against M0–M2 code, but M3's clipboard capture is exactly the kind of feature 5.1.2 scrutinizes — re-audit after M3 lands).
  - ✅ **Done 2026-08-22.** The M0/M1 scaffolding is out of Release: the `"M1"` label, the MB readout and the Diagnostics button are all `#if DEBUG`, and `DiagnosticsRunner`/`DiagnosticsPanel` no longer compile into the shipping extension at all. The strip itself remains as **reserved height** for M4's suggestion bar — re-check at M4 that what fills it is the real thing.
  - ⬜ Host app: replace the in-app privacy *statement* with a hosted privacy-policy **URL**, linked from the app and the App Store Connect listing (C-30, 5.1.1). The app now states the position accurately in-app, which satisfies 4.4's "real functionality" but **not** 5.1.1's reachable-policy requirement.
  - ⬜ Prepare App Store Connect metadata (description, screenshots, support URL, age rating, export-compliance answer — no encryption beyond iOS defaults).

**Exit criteria**
- ✅ **14 consecutive days as the default keyboard** with no jetsam disappearances and no fallback moments for plain typing.
- ✅ Paid account active; no 7-day expiry pressure.
- ✅ App-Store-readiness checklist above complete and re-verified against current App Review Guidelines immediately before submission (guidelines change; the M5-time check can go stale).

---

## M6 — v2 exploration (optional, post-daily-driver)

**Goal: the deferred list, reconsidered from a position of strength.** Only start this once M5's 14-day criterion has actually held.

**Items**
- **Glide typing spike (ADR-007):** compile FUTO Swipe's C++ beam-search library for iOS/arm64, load its small models (635 K encoder + 300 K decoder + 1.5 M ContextLM), measure memory headroom against the budget. SHARK2 template matching is the non-ML fallback. **Closes with its own go/no-go ADR.**
- **Emoji keyboard:** our own implementation (Pro-gated in KeyboardKit) with the iOS 18 scroll-gesture constraints in mind (CONSTRAINTS §8 gotcha ledger) — or keep relying on the system emoji keyboard, which is one globe-tap away.
- **Number-row toggle** and comma/period visibility settings (Gboard 16.0 parity).
- **Image/screenshot clipboard capture** behind a dedicated memory-safety spike (ADR-006).
- **Gesture delete** (backspace slide-to-select-words) — ships with the glide gesture engine or not at all.
- Revisit the deferred list in [PRODUCT.md](PRODUCT.md) §5; write ADRs for anything promoted into scope.

**Exit criteria** — none. M6 is exploratory by design; each item closes with an ADR, not a deadline.

---

## Account upgrade trigger

Buy the **$99 Apple Developer Program** at **M5** — *or immediately* if M0's Test 1 (Q-01, App Groups on a free team) fails. Do not defer past M5: 7-day expiry (C-23) on the keyboard you type with all day is the single most disruptive friction in the project.

## Parking lot

Ideas that surface mid-build land **here**, not in scope. Promotion requires an ADR.

Surfaced 2026-08-22 during the Release-trim pass — **none of these are in scope**, and none
should be built before M3 lands:

- **Unblock the comma → settings gear** (the one open M2 item). It is blocked because reaching
  the host app needs SwiftUI `Link` (C-48) and the host app's `Info.plist` declares **no
  `CFBundleURLTypes` at all** — verified 2026-08-22. Adding a URL scheme plus a `Link`-hosting
  callout is the concrete unblock. Cheap, and it is the only Gboard gesture currently missing
  outright rather than deferred by decision.
- **A settings screen** (key height, number-row toggle, haptic strength, theme). Already partly
  in M6; a real settings screen is also what guideline 4.4 expects from a host app. Needs an ADR
  because every setting is a new thing to persist, mirror (C-12) and keep working when Full
  Access is off.
- **Recompress the app icon.** `AppIcon-1024.png` is ~990 KB for a 1024² image and is now most
  of what remains in `Assets.car` (995 KB of a 3.2 MB app). No alpha channel, so no App Store
  risk either way — purely a size win.
- **iPad icon still ships** (`AppIcon76x76@2x~ipad.png`, 28 KB) despite `TARGETED_DEVICE_FAMILY`
  being iPhone-only. Small, and not worth risking a broken icon to chase.

The largest un-started dependency is not on this list because it is not an idea — it is
**📸 the Gboard-Android reference screenshots** (M0 item 7). Every 📐 MEASURE value, and both the
M1 and M2 geometry exit criteria, are blocked on them.

---

*Related docs: [PRODUCT.md](PRODUCT.md) (what each milestone delivers) · [DECISIONS.md](DECISIONS.md) (ADR-003 closes at M0) · [CONSTRAINTS.md](CONSTRAINTS.md) §10 (the Q-NN backlog M0 resolves) · [CLIPBOARD.md](CLIPBOARD.md) §9 (M3 acceptance tests) · [UI-SPEC.md](UI-SPEC.md) §12 (the 📐 MEASURE backlog).*
