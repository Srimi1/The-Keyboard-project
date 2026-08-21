# CLAUDE.md — Rules for AI working sessions

**The Keyboard Project** — a personal-use iOS keyboard extension replicating the Android Gboard layout, feel, and clipboard manager on iPhone. English-only. Not for the App Store. One user, one phone.

This file is the contract for every session. Read it first.

---

## 1. Reading order

1. **This file.**
2. **[README.md](README.md)** — status and doc map.
3. **The doc that owns your task** (table below).
4. **[docs/DECISIONS.md](docs/DECISIONS.md)** — before proposing any change to how things work.

| Your question | Authority |
|---|---|
| "Is this in scope?" | [docs/PRODUCT.md](docs/PRODUCT.md) |
| "What should this look like / do?" | [docs/UI-SPEC.md](docs/UI-SPEC.md) |
| "How is this built?" | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| **"Can iOS do this?"** | **[docs/CONSTRAINTS.md](docs/CONSTRAINTS.md) — the only valid source** |
| Anything clipboard | [docs/CLIPBOARD.md](docs/CLIPBOARD.md) |
| "Why is it this way?" | [docs/DECISIONS.md](docs/DECISIONS.md) |
| "What's next?" | [docs/ROADMAP.md](docs/ROADMAP.md) |

## 2. The ground-truth rule

**[docs/CONSTRAINTS.md](docs/CONSTRAINTS.md) is the only permissible source for iOS platform claims in this project.**

iOS keyboard extensions are a domain where confident-sounding wrong answers are cheap and expensive: undocumented memory limits, capabilities that silently no-op instead of erroring, APIs that behave differently inside an extension than in an app, and OS-version bugs that make working code fail invisibly. Every fact in CONSTRAINTS.md carries a source URL, a date, a confidence level, and an on-device-verified flag, and each is addressable by ID (`C-NN`).

- **Cite the fact ID** when a platform claim drives a decision — "we can't do X (C-05)."
- **If it isn't in CONSTRAINTS.md, you don't know it.** Say **"OPEN QUESTION — needs on-device test"** and add it to the §10 backlog as a new `Q-NN` with a test procedure. Do not guess, do not reason from how iOS "probably" works, do not import a memory of a different platform.
- **When a fact gets verified on device**, flip its flag, note the device and iOS version, and record the verdict against its `Q-NN`.
- **Never delete a fact.** Mark it `superseded` with a note.

## 3. Decision authority

[docs/DECISIONS.md](docs/DECISIONS.md) is **binding**. A recorded ADR is settled.

- To change a decision: **append a new ADR** that supersedes the old one. Never silently reverse a decision in code.
- Never relitigate a closed ADR mid-session because a different approach looks appealing.
- `Provisional` ADRs name the specific test that can overturn them — run the test, don't argue.

## 4. Hard invariants

Violating any of these is a bug, regardless of how well the code works:

1. **Two targets:** host app + keyboard extension. Nothing else.
2. **Bundle IDs are `com.<name>.*`** — never a prefix starting `se.` or `mn.`; iOS has shipped bugs where such extensions silently vanish from Settings (ADR-008).
3. **The App Group ID is one shared constant.** Never typed twice, never hardcoded at a call site.
4. **KeyboardKit is pinned to an exact version.** Major bumps require an ADR.
5. **Extension memory ≤ 40 MB steady state** (C-10). Measured, not assumed.
6. **The keyboard always types.** Every other feature degrades gracefully; typing never does (C-09).
7. **English (US) only** in v1 (ADR-002).

## 5. Platform tripwires — the do-not list

Each of these is a mistake that looks correct while writing it:

- ❌ **Never assume Full Access is on.** Gate on `hasFullAccess` at runtime. Without it: no pasteboard, no network, no haptics, no sound, no reliable App Group writes — and the haptic/sound APIs **silently no-op rather than error** (C-05, C-07).
- ❌ **Never write App Group data from the extension without checking access.** Writes fail unreliably without Full Access; settings mirror to local defaults with timestamp conflict resolution (C-12).
- ❌ **Never read UIPasteboard values outside the capture pipeline.** Every value read can fire the system "Allow Paste" alert (C-14). `changeCount` / `hasStrings` / `detectPatterns` are prompt-free — use those to detect (C-16).
- ❌ **Never add network code to the extension.** Not sync, not analytics, not crash reporting (ADR-005). Full Access unlocks network; we never use it.
- ❌ **Never paint an opaque keyboard background.** iOS 26 wraps keyboards in a system glass container; opaque backgrounds render as a gray bar (CONSTRAINTS §8 gotcha ledger).
- ❌ **Never use selector-based `UIApplication.openURL`** to open the host app — iOS 18 killed it. Use SwiftUI `Link` (CONSTRAINTS §8 gotcha ledger).
- ❌ **Never use `AVAudioPlayer` for key clicks** — wrong audio bus in extensions. Use `AudioServicesPlaySystemSound` (C-08).
- ❌ **Never assume you can read the full text field.** `documentContextBeforeInput` returns roughly the last couple of sentences (C-18).
- ❌ **Never invent a way to monitor the clipboard in the background.** It does not exist on iOS (C-13). Proposals involving background timers, silent audio, or location wakes are wrong and get apps killed.
- ❌ **Never try to "fix" an accepted limitation.** [docs/PRODUCT.md](docs/PRODUCT.md) §7 lists them; they are platform truths, not bugs.

## 6. Design fidelity

The reference is **Gboard for Android** (ADR-001) — not Gboard-iOS, not Apple's keyboard, not your sense of good keyboard design.

- [docs/UI-SPEC.md](docs/UI-SPEC.md) marks unverified visual values **📐 MEASURE**. Those must be measured from reference screenshots of a real Android device. **Do not guess them, and never let a placeholder ship as if it were verified.**
- "Better than Gboard but different" **loses by default.** The goal is muscle-memory fidelity. A change that improves on Android but breaks a learned gesture is a regression here.

## 7. Recording new findings

| You learned… | Write it to |
|---|---|
| An iOS platform fact | CONSTRAINTS.md — with source URL, date, confidence, verified flag |
| A visual measurement | UI-SPEC.md — replace the 📐 MEASURE marker with the value + how it was measured |
| A choice with alternatives | DECISIONS.md — a new ADR |
| A scope change | PRODUCT.md **and** an ADR |
| An idea that's out of scope | ROADMAP.md parking lot |

## 8. Session hygiene

- **Small, verifiable steps.** This is a project where a wrong assumption can cost days of debugging an invisible failure.
- **Every milestone exits with an on-device typing test and an Instruments `phys_footprint` measurement.** Both, every time ([docs/ROADMAP.md](docs/ROADMAP.md)).
- **Prefer on-device verification over reasoning.** When a question can be answered by running it on the phone, run it on the phone and record the answer.
- **Report failures plainly.** A silent jetsam kill, a keyboard missing from Settings, a toggle that reset — these are the project's characteristic failure modes and they don't announce themselves. If something didn't work, say so with the evidence.
