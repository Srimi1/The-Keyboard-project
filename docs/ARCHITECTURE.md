# ARCHITECTURE.md — System design

> How the pieces fit, who owns what, and which platform facts ([CONSTRAINTS.md](CONSTRAINTS.md)) forced each shape.
> Decisions referenced here are recorded in [DECISIONS.md](DECISIONS.md) — this doc implements them, it doesn't make them.

---

## 1. System overview

Two targets in one Xcode project, sharing one container:

```
┌──────────────────────────────┐         ┌──────────────────────────────┐
│      HOST APP (container)    │         │   KEYBOARD EXTENSION         │
│                              │         │   UIInputViewController      │
│  • Onboarding checklist      │         │   com.apple.keyboard-service │
│  • Settings                  │         │                              │
│  • Clipboard history viewer  │         │  • Layout + typing engine    │
│  • Capture on foreground     │         │  • Suggestion strip          │
│                              │         │  • Clipboard panel           │
│  runs: when user opens it    │         │  runs: inside OTHER apps'    │
│                              │         │        processes (C-01)      │
└───────────────┬──────────────┘         └──────────────┬───────────────┘
                │                                       │
                │      ┌─────────────────────────┐      │
                └─────▶│   APP GROUP CONTAINER   │◀─────┘
        read+write     │  • clipboard store      │   read always,
        always         │  • settings (mirrored)  │   write needs Full Access (C-12)
                       │  • personal dictionary  │
                       └─────────────────────────┘
                              no network, ever (ADR-005)
```

**The asymmetry that shapes everything:** the extension is the piece that runs constantly but has the fewest rights — limited memory (C-10), no writes to the shared container without Full Access (C-12), no network by policy (ADR-005), and it can be killed silently at any moment (C-03). The host app has full rights but runs rarely. Design accordingly: **the extension does the minimum that must happen at the keyboard, the host app does everything that can wait.**

## 2. Targets & identity

| | Host app | Keyboard extension |
|---|---|---|
| Bundle ID | `com.<name>.keyboardproject` | `com.<name>.keyboardproject.keyboard` |
| Type | iOS app | App extension (`NSExtensionPointIdentifier` = `com.apple.keyboard-service`) |
| Principal class | — | `UIInputViewController` subclass |
| Key Info.plist | — | `RequestsOpenAccess = true` (C-06) |

**Bundle-ID rule (ADR-008):** conventional `com.<name>.*` reverse-DNS only. iOS has shipped bugs where extensions with IDs starting `se.` / `mn.` **silently fail to appear** in Settings → Add New Keyboard. Choose the IDs at M0 and don't churn them — each change burns App IDs against the free account's weekly quota (C-23).

**App Group ID:** defined **once**, in a single shared constant compiled into both targets (ADR-008). Never typed twice, never hardcoded at a call site.

## 3. Framework boundary

**KeyboardKit 10 free tier**, pinned to an exact SPM version (ADR-003 — provisional until the M0 spike).

| KeyboardKit owns | We own |
|---|---|
| SwiftUI keyboard view hosting | Gboard layout definition + geometry ([UI-SPEC.md](UI-SPEC.md)) |
| Dynamic layout engine | **Clipboard manager** (store, capture, panel) |
| Input & action callouts | Theme palettes and styling values |
| Gesture recognition plumbing | Suggestion strip + autocorrect engine |
| Audio/haptic feedback plumbing | Toolbar |
| Text-proxy utilities | Host app entirely |

**Adapter rule.** KeyboardKit types stay behind **thin adapters in code we own** wherever that's cheap — a `KeyboardLayoutProvider` we define, our own key-model type, our own theme type. The framework is a closed binary from effectively a single maintainer; the fallback (a pinned fork of MIT KeyboardKit 9.9.0) must stay tractable. Don't spread framework types through the clipboard or autocorrect code, which have no reason to know the framework exists.

## 4. Data layer

### Clipboard store

```
ClipboardItem
  id          UUID
  text        String        // text only in v1 (ADR-006)
  createdAt   Date          // drives 1-hour expiry
  pinned      Bool          // pinned items never expire
  contentHash String        // dedupe alongside changeCount
  sourceHint  String?       // best-effort origin, nil when unknown
```

File-backed in the App Group container, **memory-mappable** — the store must be readable without loading everything into the extension's memory (C-10). Hard caps on item size and item count, enforced at write time, chosen at M3.

### Settings

Settings are written by the host app and read by the extension. Because extension writes are unreliable without Full Access (C-12), settings are **mirrored** in both the shared container and the extension's local defaults, with **timestamp-based conflict resolution**: each key carries a last-written timestamp; the newer value wins on read. This is what production keyboards do, and it's the reason a settings change made in the host app appears in the keyboard even when the extension can't write back.

### Personal dictionary

Words accepted by the user learn into the App Group store (ADR-009). Written from the extension when Full Access allows; otherwise queued in local defaults and reconciled the next time the host app runs.

## 5. Clipboard capture pipeline

The pipeline is entirely shaped by one fact: **iOS has no background clipboard monitoring** (C-13). We can only capture when our code is running.

```
TRIGGER (one of three)
  ├─ keyboard becomes visible          (extension)
  ├─ changeCount poll while visible    (extension, timer)
  └─ host app enters foreground        (host app)
        │
        ▼
DETECT — changeCount != lastSeen && hasStrings     ← prompt-free (C-16)
        │  no change → stop, cost nothing
        ▼
READ — UIPasteboard.general.string                 ← the only prompting call (C-14)
        │  requires Full Access (C-05) + "Paste from Other Apps = Allow" (C-15)
        ▼
DEDUPE — by changeCount, then contentHash
        │  already stored → bump nothing, stop
        ▼
STORE — append to App Group store, enforce size/count caps
        │
        ▼
SWEEP — delete unpinned items older than 1 hour
```

**Failure behavior at each stage:** no Full Access → skip the whole pipeline, panel shows its no-access state. Read prompts appear anyway (Q-05 unresolved) → fall back to explicit tap-to-capture rather than automatic reads. Store unavailable → keyboard still types; clipboard degrades to empty. **Nothing in this pipeline may block typing.**

Detection is free — `changeCount` and `hasStrings` never prompt (C-16) — so poll cheaply and read rarely. Full spec: [CLIPBOARD.md](CLIPBOARD.md).

## 6. Typing pipeline

```
touch → key model (layer + shift state) → action
                                            ├─ character  → textDocumentProxy.insertText
                                            ├─ backspace  → deleteBackward (+ repeat timer)
                                            ├─ cursor      → adjustTextPosition(byCharacterOffset:)
                                            ├─ layer switch → state machine, no proxy call
                                            └─ globe      → handleInputModeList (C-21)
```

**Context limits.** `documentContextBeforeInput` returns roughly the last couple of sentences — never the full document (C-18). Auto-capitalization, double-space-period, and the correction engine all read from that window and must behave correctly when it's short or empty. **Never assume more context than the API returns**, and never implement cursor-moving tricks to reconstruct more — they're fragile and out of scope.

## 7. Autocorrect pipeline

```
word being typed
   ├─ UITextChecker      → guesses + completions       (works without Full Access, C-19)
   ├─ UILexicon          → contacts + text replacements (requestSupplementaryLexicon)
   └─ frequency dict     → ranking (memory-mapped, C-10)
         ▼
   candidates → rank → 3 strip slots (middle = autocorrect, literal always reachable)
         ▼
   space pressed → commit middle candidate if confidence ≥ threshold
         ▼
   backspace immediately after → revert to literal input
         ▼
   accepted word not in dictionaries → learn into personal dictionary
```

Thresholds are **conservative by design** (ADR-009): under-correcting is an annoyance, over-correcting is why people uninstall keyboards. There is no access to Apple's autocorrect engine (C-19) — this pipeline is the whole story.

## 8. Feedback subsystem

`UIImpactFeedbackGenerator` for haptics, `AudioServicesPlaySystemSound` for clicks (not `AVAudioPlayer` — wrong audio bus in extensions, C-08). Both sit behind a single feature gate on `hasFullAccess` and **degrade silently** — the APIs already no-op without Full Access (C-07), so the gate exists to avoid pointless work, not to prevent errors.

## 9. Degradation matrix

**The invariant: the keyboard always types.** Everything else is optional.

| Condition | Typing | Clipboard | Haptics/sound | Settings | User sees |
|---|---|---|---|---|---|
| Full Access **off** | ✅ | ❌ | ❌ | read-only (C-12) | Panel explains + links to host app |
| Host app **never opened** | ✅ | ✅ (capture works) | ✅ | defaults | Nothing unusual |
| App Group **unavailable** | ✅ | ❌ | ✅ | local only | Panel shows empty state |
| **Secure / phone-pad field** | n/a — system keyboard takes over (C-20) | | | | Stock keyboard appears |
| Host app **bans extensions** | n/a — banned (C-20) | | | | Stock keyboard appears |
| Paste prompts **still appear** (Q-05) | ✅ | manual capture only | ✅ | ✅ | Tap chip to capture |

## 10. Memory strategy

**Budget: ≤ 40 MB steady state**, against a jetsam ceiling around ~60 MB that kills **silently, with no crash log** (C-10). A keyboard that vanishes mid-sentence is the worst failure this project can ship.

Rules:
- **Memory-map** the frequency dictionary and clipboard store rather than loading them (a documented 52 MB → 27 MB win in a comparable keyboard).
- **No heavy visual effects** — gradients, shadows, and blur measurably worsen the per-appearance leak pattern (C-02).
- **Text-only clipboard** (ADR-006) — images are the fastest route to a kill.
- **Lazy-construct** the clipboard panel and any secondary UI; build on first open, not at launch.
- **`deinit` hygiene:** empty heavy views on teardown, deferred one runloop turn — each host app creates a fresh controller whose view is retained after dismissal (C-02).

**Profiling is a milestone gate, not a final step.** Every milestone exits with an Instruments `phys_footprint` measurement recorded in [ROADMAP.md](ROADMAP.md). Measure on the oldest device that will actually be used.

## 11. Host app architecture

The host app exists to do what the extension can't, and App Review would require it to have real functionality anyway if this were ever published (C-30).

- **Onboarding state machine**, with live status detection at each step: *keyboard added* → *Full Access enabled* → *"Paste from Other Apps" = Allow*. Because a re-signing cycle on the free account can reset toggles (C-23, ADR-004), this screen is also the diagnostic — a lost toggle is visible in seconds instead of surfacing as "the clipboard mysteriously stopped working."
- **Settings** — writes to the shared container (§4).
- **Clipboard history viewer/manager** — the full-size counterpart to the keyboard panel: browse, pin, delete.
- **Foreground capture** — the host app is one of the three capture triggers (§5).
- **Opening the host app from the keyboard:** SwiftUI `Link` only. iOS 18 killed the selector-based `openURL` trick (CONSTRAINTS §8 gotcha ledger).

---

*Related docs: [CONSTRAINTS.md](CONSTRAINTS.md) (every platform fact cited above) · [DECISIONS.md](DECISIONS.md) (the choices being implemented) · [CLIPBOARD.md](CLIPBOARD.md) (capture pipeline in full) · [UI-SPEC.md](UI-SPEC.md) (what the views render) · [ROADMAP.md](ROADMAP.md) (build order and memory gates).*
