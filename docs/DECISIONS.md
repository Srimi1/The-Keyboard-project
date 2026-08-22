# DECISIONS.md — Architecture Decision Record

> **This log is binding.** A decision recorded here is settled. To change one, append a **new ADR** that supersedes the old one (mark the old `Superseded by ADR-NNN`) — never silently reverse a decision in code, and never relitigate a closed ADR in a working session.
>
> **Format:** `ADR-NNN` · Date · Status (`Accepted` / `Provisional` / `Superseded by …`) · Context · Decision · Consequences.
> `Provisional` means the decision stands but a named test in [ROADMAP.md](ROADMAP.md) M0 can overturn it — that test is written into the ADR.
> Append only. History is never edited.

---

## ADR-001 — Gboard (Android) is the reference product

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** The project exists because the iPhone keyboard doesn't feel like Android's. "Feels like Android" needs one concrete referent, not an average of Android keyboards — Samsung Keyboard and SwiftKey have different layouts, toolbars, and symbol placement. The owner's muscle memory is Gboard's.

**Decision.** Gboard for **Android** is the single visual and behavioral blueprint. Where Gboard-Android and Gboard-iOS differ, **Android wins** — Gboard-iOS is frozen at v2.3.19 (May 2022) and lacks the clipboard manager, number row, toolbar customization, and gesture delete entirely (C-17). Apple's stock keyboard is a baseline for iOS conventions only (globe key handling per C-21), never a design target.

**Consequences.** Layout geometry follows AOSP LatinIME percentages, the closest primary source to Gboard's closed-source metrics ([UI-SPEC.md](UI-SPEC.md)). Ambiguous visual details get **measured from screenshots of a real Android device**, not guessed — those are logged as measurement TODOs in UI-SPEC. Pin the reference Gboard version when capturing screenshots so the target doesn't drift under us.

---

## ADR-002 — English (US) only in v1

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** Multilingual support means new layouts, per-locale callout sets, per-locale dictionaries, and a language-switch UX. It multiplies every layout and autocorrect task. The owner types English.

**Decision.** v1 ships **English (US) only**. The spacebar carries the "English (US)" label for Gboard fidelity, but there is no second locale behind it. Layout variants (QWERTZ/AZERTY) and new scripts are out.

**Consequences.** The layout engine still keeps locale as a parameter rather than hardcoding — cheap now, expensive to retrofit. This also sidesteps the area where KeyboardKit's free-tier coverage is most ambiguous (Q-08). Revisiting this needs a new ADR.

---

## ADR-003 — Build on KeyboardKit 10 free tier, not from scratch and not Pro

**Date:** 2026-08-21 · **Status:** **Provisional** — confirmed or overturned by the M0 spike (Q-02 + layout expressiveness + memory floor)

**Context.** Three options were researched. **From scratch:** you own the multi-touch/slide-off touch engine, key-preview popups, long-press callout menus, shift/caps/delete-repeat logic, and layout math — research estimates 2–4× the calendar time to daily-drivable (which is 2–4 months part-time *even with* a framework). **KeyboardKit Pro:** $50–500/mo, priced for businesses. **Fleksy SDK:** ~$269/mo B2B, closed, white-label. **KeyboardKit 10 free tier:** closed-source binary XCFramework via SPM, iOS 16+, "free to start using" with no license key, covering the SwiftUI keyboard view, a dynamic layout engine, input/action callouts, gestures, audio+haptic feedback plumbing, styling, and proxy utilities.

Decisive finding: **none of this project's differentiators are Pro-gated.** The clipboard manager, Gboard theming, and v1 autocorrect are ours to build on every path. And **neither** free nor Pro ships glide typing — so building from scratch buys no glide advantage either.

**Decision.** Build on **KeyboardKit 10 free tier**, pinned to an exact SPM version. Do not buy Pro. Do not use Fleksy. Do not build the commodity 80% from scratch.

**M0 exit tests that could overturn this** — all three must pass:
1. The Gboard bottom row (`[?123][,][space][.][return]`) and ~1.5× shift/backspace are expressible in the free layout engine.
2. No license/network validation misbehaves inside the extension with the device offline (Q-02).
3. Baseline memory floor leaves room inside the ≤40 MB budget (C-10).

**Fallback if overturned:** a pinned fork of **MIT-licensed KeyboardKit 9.9.0** (iOS 15+, source-readable, forkable). Last resort: from scratch, studying **azooKey** (MIT, SwiftUI, actively maintained) as the modern reference implementation.

**Consequences.** KeyboardKit is a closed binary from effectively a single maintainer — so KeyboardKit types stay behind **thin adapters in code we own** wherever that's cheap, keeping a swap tractable ([ARCHITECTURE.md](ARCHITECTURE.md)). Major version bumps (e.g. KeyboardKit 11, which raises the floor to iOS 17+) require a new ADR, never a casual upgrade.

---

## ADR-004 — Start on the free personal team; buy the $99 program at daily-driver stage

**Date:** 2026-08-21 · **Status:** Superseded by ADR-010 (distribution target changed from personal-only to public App Store; the free-team-until-M5 provisioning plan itself is unchanged)

**Context.** Everything this project needs works on free provisioning: the keyboard extension point needs no paid entitlement (C-24), Full Access is an Info.plist key plus a user toggle rather than a provisioned entitlement (C-06), and App Groups is listed as free-team-supported (C-25). The free tier's cost is friction: 7-day profile expiry, 3 apps, 10 App IDs of which host + extension consume 2 (C-23).

**Decision.** **Start free.** Upgrade to the **$99/yr Apple Developer Program at M5** (daily-driver hardening) — or **immediately** if the M0 App Groups test (Q-01) fails. **AltStore/SideStore are rejected**: same 7-day limits, they rewrite app-group identifiers per signing account (a direct breakage risk for this architecture), they can strip extensions entirely, and no first-hand report confirms keyboards work through them (C-28).

**Consequences.** While free, the keyboard **dies weekly** until re-deployed from Xcode — the worst failure mode for the thing you type on all day. Mitigations: Wi-Fi deploy (C-29), a recurring calendar reminder, and keeping the system keyboard enabled as fallback. After upgrading: 1-year development signing or TestFlight internal builds (90-day OTA, C-27) end the ritual. The App Group ID must never be hardcoded in a way that assumes a fixed team prefix.

---

## ADR-005 — The clipboard manager requires Full Access + App Groups, and is local-only forever

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** Reading UIPasteboard requires Full Access (C-05), and reliable App Group writes from the extension do too (C-12). Full Access simultaneously unlocks network — which is precisely the capability a keyboard should never use, and precisely what makes users distrust third-party keyboards.

**Decision.** The clipboard manager depends on Full Access + App Groups. **No network code exists anywhere in the extension** — not analytics, not sync, not crash reporting. All clipboard data lives in the App Group container on-device. Every Full-Access-dependent feature is gated at runtime on `hasFullAccess` with graceful degradation: **the keyboard must always still type** (C-09).

**Consequences.** Onboarding must walk three steps (add keyboard → Full Access → "Paste from Other Apps" = Allow) with live status detection in the host app, so a toggle reset after a re-signing cycle is visible in seconds rather than discovered as "the clipboard mysteriously stopped working" ([CLIPBOARD.md](CLIPBOARD.md)). The no-network rule also keeps a hypothetical future App Store review clean against 4.4.1 and 5.1.2 (C-30).

---

## ADR-006 — Clipboard is text-only in v1

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** Gboard-Android captures text, URLs, and images (including screenshots). Images decoded in the extension process are the fastest route to a jetsam kill under the ~60 MB ceiling, and jetsam kills are **silent** — the keyboard just vanishes mid-typing (C-10, C-03).

**Decision.** v1 captures **text (including URLs as text) only.** Images and screenshot capture are deferred behind a dedicated memory-safety spike (M6).

**Consequences.** Item size and count caps are part of the store design from day one, not added later. Text covers the overwhelming majority of real personal clipboard value, so the product cost is small and the stability win is large.

---

## ADR-007 — Glide typing is deferred to v2

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** Glide typing is the single hardest feature in scope. It is feasible in an extension (Gboard-iOS and SwiftKey ship it), but **KeyboardKit neither free nor Pro provides it**, and no open-source iOS implementation exists. The only credible open path is **FUTO Swipe** (released ~June 2026): a 635 K-parameter layout-agnostic encoder + 300 K QWERTY decoder + 1.5 M ContextLM with a C++ beam-search inference library (GPL — fine for personal use), models under the FUTO Model License, never ported to iOS. Classic **SHARK2** template matching is the non-ML fallback.

**Decision.** Not in v1. **M6** runs a go/no-go spike: compile FUTO Swipe's C++ library for iOS/arm64, load the models, measure memory headroom against the budget. That spike closes with its own ADR.

**Consequences.** v1 is a tap-typing keyboard, and PRODUCT.md says so plainly so no session treats glide as an implied requirement. Gesture delete (backspace slide-to-select-words) rides on the same continuous-gesture engine and is deferred with it. The small model sizes suggest the memory budget *can* accommodate it — that's what makes the spike worth running rather than abandoning. Note the FUTO Model License is fine for private use but unclear for redistribution, which matters only if ADR-004's personal-use scope ever changes.

---

## ADR-008 — Bundle IDs use `com.<name>.*`; the App Group ID lives in one shared constant

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** iOS has repeatedly shipped bugs where keyboard extensions with certain bundle-ID prefixes silently fail to appear in Settings → Add New Keyboard (`mn.` on iOS 13, `se.` on iOS 17.2–17.3.1). The failure mode is invisible: no error, the keyboard simply isn't listed. Separately, app-group identifiers get rewritten by sideloading tools (C-28), and a group string duplicated across two targets drifts.

**Decision.** Conventional reverse-DNS **`com.<name>.*`** bundle IDs for both targets, chosen at M0 and never changed casually (changing them costs App IDs against the weekly free-account quota, C-23). The **App Group identifier is defined once** in a single shared constant referenced by both targets — never typed twice, never hardcoded at a call site.

**Consequences.** Cheap insurance against a debugging session that would otherwise go looking for a code bug that doesn't exist.

---

## ADR-009 — Autocorrect is UITextChecker + UILexicon + a bundled frequency dictionary, and will be worse than Gboard

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** Apple exposes **no** system autocorrect engine to extensions (C-19). The available primitives are `UITextChecker` (guesses/completions) and `requestSupplementaryLexicon` (contact names + Settings text replacements), both working without Full Access. Google's stack is ML-based and unavailable. Weak autocorrect is the top reason people abandon third-party keyboards.

**Decision.** v1 autocorrect = `UITextChecker` + `UILexicon` + a bundled, memory-mapped word-frequency dictionary for ranking, with **conservative correction thresholds** — correct only on high confidence. The literal typed string is **always** a reachable candidate; **backspace immediately after a correction reverts it**. Accepted words learn into a personal dictionary in the App Group store. Next-word prediction waits until correction itself feels safe.

**Consequences.** "Good enough, not Gboard-equal" is a stated product truth in [PRODUCT.md](PRODUCT.md), not a defect to be fixed by a future session inventing an API that doesn't exist. Tuning happens against the owner's real typing over M4, with a misfire log driving threshold changes. Under-correcting is the intended failure direction: a missed correction is an annoyance, a wrong correction that destroys a word is why people uninstall keyboards.

---

## ADR-010 — Distribution target is the public App Store, not personal sideload only

**Date:** 2026-08-21 · **Status:** Accepted

**Context.** ADR-004 and [PRODUCT.md](PRODUCT.md) §6 fixed distribution as "personal sideload / TestFlight only," with App Store submission listed as a rejected non-goal — App Review guidelines were recorded in C-30 purely as a hedge, "so a future decision isn't made blind." That future decision has now been made: the owner wants this shipped on the App Store, matching Apple's security/privacy/review standards, not just running on one personal device. Two things this reverses concretely: (1) every App-Review-only requirement in C-30 (4.4, 4.4.1, 5.1.1, 5.1.2) moves from "recorded for later" to "must actually be satisfied before submission," and (2) a **Privacy Manifest (`PrivacyInfo.xcprivacy`) is now mandatory** — Apple has required one since May 1, 2024 for any app using a "required-reason API," and this project's heavy `UserDefaults`/App Group usage (C-12) and file-timestamp reads squarely qualify (new fact **C-31**). Neither target currently ships a `PrivacyInfo.xcprivacy` file (verified by repo search, 2026-08-21) — this is a real gap, not a hypothetical one, tracked as an M5 exit item below.

What this decision does **not** change: the architecture stays single-tenant — no accounts, no sign-in, no server, no cross-device sync (that non-goal in PRODUCT.md §6 is about the app never having a backend, which is orthogonal to how many individual people install their own private copy from the store). The no-network rule (ADR-005) is untouched and becomes *more* load-bearing, since it's also what keeps the app clean against 4.4.1/5.1.2. English-only (ADR-002) is untouched — that's a v1 scope decision, not a distribution one. ADR-004's actual provisioning mechanics (stay on the free personal team through M2–M4, buy the $99/yr Apple Developer Program at M5) are **also unchanged in timing** — a paid Program membership is required for *any* distribution method including TestFlight, so the existing M5 upgrade point already sits before the point it would first be needed. What changes is only the destination after that upgrade: App Store Connect submission for public release, not a permanent personal TestFlight/ad-hoc install.

**Decision.** Target **public App Store release** once v1 (through M5) is complete and passes an App-Store-readiness check. Concretely, before any submission:
- Ship a correct `PrivacyInfo.xcprivacy` in both targets declaring the required-reason API categories actually used (C-31) and `NSPrivacyCollectedDataTypes` accurately reflecting that **zero data leaves the device** — no tracking domains, no collected data types tied to the user's identity.
- Satisfy C-30 (4.4 real host-app functionality — already true, the host app has onboarding/settings/diagnostics; 4.4.1 keyboard-specific rules — already true per ADR-005/ADR-009; 5.1.1 a reachable privacy-policy link in the host app and App Store Connect listing — not yet built; 5.1.2 — already true, nothing is collected to profile).
- Buy the $99 Apple Developer Program at M5 as ADR-004 already planned, this time explicitly as the App Store Connect enrollment, not just a TestFlight/ad-hoc convenience.
- Write App Store Connect metadata (description, screenshots, support URL, privacy-policy URL, age rating, export-compliance answer — this app does no encryption beyond what iOS provides by default).

**Consequences.** PRODUCT.md §6's "App Store distribution — never" line is reversed; PRODUCT.md is updated in the same session to point here instead of restating the old non-goal. CONSTRAINTS.md C-30 is re-verified against current (2026-08-21) guideline text and its framing changed from "hypothetical" to "binding requirement"; new fact C-31 records the Privacy Manifest requirement. ROADMAP.md M5 gets explicit App-Store-readiness exit items (privacy manifest, privacy-policy URL, App Store Connect listing) alongside its existing daily-driver-hardening criteria — submission should not be attempted before M5's 14-day daily-driver bar is met regardless of technical review-readiness, since a keyboard that doesn't survive as a daily driver on the owner's own phone has no business being offered to anyone else's. This ADR does not itself claim the app is ready to submit — only that submission is now the intended endpoint, with the concrete gap list above still open.

---

## ADR-011 — Development instrumentation compiles out of Release; the extension writes one handshake instead

**Date:** 2026-08-22 · **Status:** Accepted

**Context.** The M0 harness was written to answer Q-01/Q-03/Q-05 from inside the extension process, which is the only place those answers mean anything. It was never gated, so it shipped: in a **Release** build, every `viewWillAppear` — that is, every time the keyboard appeared, in every host app — ran `AppGroup.probeAvailability()` (a UUID file write, read-back and delete in the shared container), a `UIPasteboard` `changeCount`/`hasStrings` probe, a JSON encode and a second write with a read-back verify, and started a **1 Hz `Timer`** that ran for as long as the keyboard was visible. That is disk I/O and IPC on the critical path of the keyboard appearing, against a ≤ 40 MB budget and an invariant that says the keyboard always types (C-09, C-10).

It was also **dead work**. `KeyboardViewModel.diagnostics` is a plain `let`, and a nested `ObservableObject` does not forward `objectWillChange`, so the memory figure the timer computed never reached the strip that displayed it. The number on screen was frozen at its first value.

Alternatives considered:
- **Delete the diagnostics entirely.** Smallest tree, but ROADMAP requires an on-device `phys_footprint` reading at every milestone exit, and Instruments cannot easily attach to a keyboard extension running inside another app's process (that is *why* the keyboard reports its own footprint). Deleting the instrument would leave a required gate with no way to measure it.
- **Leave the code compiled in and only stop the runtime work.** Fixes the CPU and disk cost but keeps ~450 lines of unreachable code in the shipped extension, and leaves the trap in place for the next person who calls into it.
- **Gate the runtime work only in the extension, keep it in the host app.** The host app has no memory budget, but it was also probing the container on every foreground for no user-visible reason.

**Decision.** `DiagnosticsRunner` and `DiagnosticsPanel` are wrapped in `#if DEBUG` at file level, `KeyboardViewModel.diagnostics` exists only in Debug, and every call site is gated. Debug builds keep the full harness — and the nested-observable bug is fixed there, so the readout actually updates.

What the shipping extension writes instead is `KeyboardHandshake` (`Sources/Shared`): `lastSeenAt`, `hasFullAccess`, `appVersion`, written **off the main thread** and only when the payload changed or the stored record is older than 6 h. That is the minimum the host app's setup checklist needs, because whether Full Access is on is a fact only the extension can read (C-06) and has no notification path (C-41).

The keyboard's strip keeps its **height** in Release but renders nothing. Collapsing it would make the shipping keyboard 28 pt shorter than the Debug build, than every geometry measurement taken so far, and than the space M4's suggestion bar will occupy (UI-SPEC §7).

**Consequences.** The Release extension binary drops to ~901 KB with **zero** `DiagnosticsRunner`/`DiagnosticsPanel` symbols (verified with `nm`), and the whole app to 3.2 MB. Step 3 of onboarding ("Paste from Other Apps") can no longer be *confirmed* in Release, because confirming it requires a pasteboard value read — the one call that can prompt (C-14); it is presented as an instruction until M3's capture pipeline needs the value in the course of doing real work. `DiagnosticsReport`/`DiagnosticsStore` survive for the Debug panel and the host app's Developer section. Anyone adding instrumentation to the extension from here on must gate it the same way — an ungated probe in `viewWillAppear` is the specific mistake this ADR exists to prevent.

---

## Template for new ADRs

```markdown
## ADR-NNN — <decision in one line, stated as a choice made>

**Date:** YYYY-MM-DD · **Status:** Accepted | Provisional (test that resolves it) | Superseded by ADR-NNN

**Context.** What forced a decision. Cite CONSTRAINTS.md fact IDs (C-NN) for platform grounds and
name the alternatives actually considered — a decision with no rejected alternative isn't a decision.

**Decision.** What we do. Concrete enough to be checkable in code review.

**Consequences.** What this makes easy, what it makes hard, what it commits us to, and what
now has to be true elsewhere (docs to update, tests to add, follow-on work).
```

---

*Related docs: [CONSTRAINTS.md](CONSTRAINTS.md) (the facts these decisions rest on) · [PRODUCT.md](PRODUCT.md) (scope these decisions define) · [ARCHITECTURE.md](ARCHITECTURE.md) (how they're implemented) · [ROADMAP.md](ROADMAP.md) (M0 resolves the provisional ones).*
