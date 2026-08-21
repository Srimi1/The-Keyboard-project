# ROADMAP.md — From empty folder to daily driver

> The work queue. Each milestone has **items** and **exit criteria** — a milestone isn't done because the items are checked off, it's done when the exit criteria are demonstrably met on a real device.
>
> **Every milestone exits with two universal gates:** (1) an on-device typing test, and (2) an Instruments `phys_footprint` measurement ≤ **40 MB** (C-10). No exceptions — a keyboard that vanishes mid-sentence is the worst failure this project can ship.

---

## Status

| Milestone | Goal | Status |
|---|---|---|
| **M0** | Foundations & feasibility spike | **← current** |
| M1 | Typeable Gboard QWERTY | not started |
| M2 | Gboard feel — long-press, gestures, feedback | not started |
| M3 | Clipboard manager | not started |
| M4 | Suggestions & autocorrect | not started |
| M5 | Daily-driver hardening + paid account | not started |
| M6 | v2 exploration (optional) | not started |

**Docs phase:** complete (2026-08-21). This doc set exists; M0 begins after review.

---

## M0 — Foundations & feasibility spike

**Goal: kill the unknowns before writing product code.** Three research questions could each invalidate a chunk of the plan; find out now, not in month two. ~1 week.

**Items**

1. ✅ **Done 2026-08-21.** Xcode project created via XcodeGen (`project.yml`): `KeyboardProject` host app + `KeyboardExtension`, bundle IDs `com.srimi.keyboardproject{,.keyboard}` (ADR-008), `RequestsOpenAccess = true` (C-06), App Group `group.com.srimi.keyboardproject` on both targets. Builds clean for the simulator with signing disabled; extension verified embedded in `PlugIns/` with the correct `NSExtension` dictionary. Ships a dependency-free keyboard (Gboard row structure + AOSP bottom-row widths) and an in-keyboard diagnostics panel that runs the tests below.
2. ⬜ Deploy to the iPhone on the free personal team: enable Developer Mode (C-26), trust the profile, set up Wi-Fi deployment (C-29). **Needs hardware — blocks items 3–5.**
3. **🔬 EMPIRICAL TEST 1 — App Groups on a free team (Q-01).** Capability is wired on both targets and the probe is built: open the keyboard → **Diagnostics**, then open the host app and confirm it displays the report the keyboard wrote. Record the verdict in CONSTRAINTS.md and flip C-25's verified flag. **If it fails → buy the $99 program that day** (ADR-004); the clipboard architecture depends on it.
   *Simulator note: the probe reports "working" in the simulator, but the simulator has no provisioning profile, so that is evidence about the code — not about the account. The app labels it as inconclusive; only a real-device run closes Q-01.*
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
- Implement the 4-row layout per [UI-SPEC.md](UI-SPEC.md) §1: 10/9/7 letter rows, centered home row, 15% shift/backspace, AOSP bottom-row widths, spacebar labeled "English (US)".
- Layers: base, shifted, caps-lock, `?123`, `=\<` with correct layer-switch keys (§2).
- Shift state machine: tap, double-tap caps lock, auto-capitalization from `documentContextBeforeInput` (C-18).
- Backspace hold-repeat with acceleration; return-key context labels.
- Globe key conditional on `needsInputModeSwitchKey`, wired to `handleInputModeList` (C-21).
- Key-preview popup on press; slide-off cancellation (§3–4).
- Light + dark palettes (§9) with a **transparent** keyboard background for iOS 26 Liquid Glass (CONSTRAINTS §8 gotcha ledger).
- Keyboard height per device class, handling the initial-height flicker (C-22, §11).

**Exit criteria**
- ✅ A full day of plain typing in Messages/Notes/Safari without switching to the stock keyboard.
- ✅ Side-by-side against reference screenshots: no obvious geometry deltas.
- ✅ ≤ 40 MB.

---

## M2 — Gboard feel: long-press, gestures, feedback

**Goal: muscle memory transfers.** This is the milestone that decides whether it *feels* like Android or merely *looks* like it.

**Items**
- Long-press system ([UI-SPEC.md](UI-SPEC.md) §5): accent callouts, q–p → 1–0 digit hints with corner glyphs, period → punctuation grid, comma → settings-gear mini-popup.
- Double-space → period with the correct timing window; immediate backspace reverts.
- Spacebar slide cursor control via `adjustTextPosition` with Gboard-like thresholds (§6).
- Haptics + key click sound, gated on `hasFullAccess`, silent degradation (C-07, C-08).
- Resolve the remaining 📐 MEASURE items from the reference screenshots — especially **V-06, the period long-press grid contents and ordering**.
- Side-by-side screenshot comparison; fix every visible delta.

**Exit criteria**
- ✅ You (the Android Gboard user) report **no muscle-memory misses** on layout or long-press over a full day.
- ✅ All V-01…V-08 measurements resolved and reflected in UI-SPEC.md.
- ✅ ≤ 40 MB.

---

## M3 — Clipboard manager ⭐

**Goal: the flagship feature works end-to-end.** This is the reason the project exists.

**Items**
- App Group clipboard store: schema, file-backed persistence, dedupe (changeCount + content hash), size/count caps ([ARCHITECTURE.md](ARCHITECTURE.md) §4).
- Capture pipeline: read on keyboard appear, `changeCount` poll while visible, capture on host-app foreground (§5).
- Retention: 1-hour sweep for unpinned; pinned persist.
- Panel UI: Recent + Pinned replacing the key area, tap-to-insert, long-press pin/delete, empty and no-Full-Access states ([UI-SPEC.md](UI-SPEC.md) §8).
- Paste chip in the suggestion strip after a fresh copy.
- Host app: full clipboard history viewer/manager + the 3-step onboarding flow with live status detection.
- Resolve **Q-09** (password-manager pasteboard hints) and record it.

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
- **Buy the $99 Apple Developer Program** (ADR-004). Move to 1-year development signing or TestFlight internal builds (90-day OTA, C-27). Retire the weekly re-sign ritual.
- Memory audit with Instruments across heavy usage: long sessions, panel open/close cycles, many different host apps. Fix the `UIInputViewController` retention leaks (C-02). Verify on the oldest device in use.
- Edge-case sweep: secure/phone-pad fallback (C-20), apps that ban third-party keyboards, orientation changes, Full Access toggled off mid-session, empty/cleared pasteboard.
- iOS-version check on the current release: Liquid Glass background, height behavior, gesture handling. Update the C-26 gotcha ledger with anything new.
- Set as **default keyboard**; 2-week burn-in with an issue log; fix everything that made you switch back.

**Exit criteria**
- ✅ **14 consecutive days as the default keyboard** with no jetsam disappearances and no fallback moments for plain typing.
- ✅ Paid account active; no 7-day expiry pressure.

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

- *(empty — add as they come up)*

---

*Related docs: [PRODUCT.md](PRODUCT.md) (what each milestone delivers) · [DECISIONS.md](DECISIONS.md) (ADR-003 closes at M0) · [CONSTRAINTS.md](CONSTRAINTS.md) §10 (the Q-NN backlog M0 resolves) · [CLIPBOARD.md](CLIPBOARD.md) §9 (M3 acceptance tests) · [UI-SPEC.md](UI-SPEC.md) §12 (the 📐 MEASURE backlog).*
