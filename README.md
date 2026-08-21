# The Keyboard Project

**An iPhone keyboard that feels like Gboard on Android.**

Switching from Android to iPhone costs you two things you notice every single day: the **layout** — key positions, the bottom row, what happens when you long-press — and the **clipboard**. Android's Gboard keeps a history of what you copied. iOS keeps exactly one item, forever, with no history at all.

Nobody fixes this. **Gboard for iOS is frozen at v2.3.19 (May 2022)** — Google stopped developing it, and it never had the clipboard manager. Apple's keyboard doesn't either. So this project builds it: a personal-use iOS keyboard extension that replicates the Gboard-Android layout and feel, with the clipboard manager that neither Google nor Apple ships on iPhone.

**Success looks like:** *"I use this keyboard all day, by choice, and never switch back."*

---

## Status

| | |
|---|---|
| **Phase** | Documentation complete → **M0 (Foundations & feasibility spike)** |
| **Docs written** | 2026-08-21 |
| **Dev account** | Free personal team (upgrade to $99/yr at M5 — [ADR-004](docs/DECISIONS.md)) |
| **Framework** | KeyboardKit 10 free tier — **provisional**, confirmed by the M0 spike ([ADR-003](docs/DECISIONS.md)) |
| **Language** | English (US) only in v1 ([ADR-002](docs/DECISIONS.md)) |
| **Target device / iOS** | *(fill in at M0)* |
| **Code** | None yet — M0 creates the Xcode project |

## Documentation map

Read in this order the first time. After that, jump to whichever doc owns your question.

| Doc | What it owns | Read it when |
|---|---|---|
| **[CLAUDE.md](CLAUDE.md)** | Rules for AI working sessions | **First**, every session |
| **[docs/PRODUCT.md](docs/PRODUCT.md)** | Scope: v1 features, deferred, non-goals, accepted limitations, the Gboard parity matrix | "Is X in scope?" |
| **[docs/UI-SPEC.md](docs/UI-SPEC.md)** | The layout blueprint: key geometry, layers, long-press maps, gestures, panels, themes | "What does X look like / do?" |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Targets, App Group data flow, framework boundary, the typing/clipboard/autocorrect pipelines, memory strategy | "How is X built?" |
| **[docs/CONSTRAINTS.md](docs/CONSTRAINTS.md)** | **Every iOS platform fact**, with source, date, confidence, verified flag — plus the open-question backlog | "Can iOS even do X?" — **the only valid source** |
| **[docs/CLIPBOARD.md](docs/CLIPBOARD.md)** | The flagship feature: capture model, permissions, retention, panel, acceptance tests | Anything clipboard |
| **[docs/DECISIONS.md](docs/DECISIONS.md)** | ADR log — binding decisions with rationale | "Why is it this way?" — **before** proposing a change |
| **[docs/ROADMAP.md](docs/ROADMAP.md)** | M0–M6 with items and exit criteria | "What's next?" |
| **[docs/reference/](docs/reference/)** | Raw research corpus (`research-2026-08-21.json`), Gboard reference screenshots (from M0) | Sourcing a new fact |

## Quick facts

| | |
|---|---|
| Targets | Host app + keyboard extension (`UIInputViewController`, `com.apple.keyboard-service`) |
| Bundle IDs | `com.<name>.keyboardproject` / `com.<name>.keyboardproject.keyboard` — **never** prefixes starting `se.` or `mn.` ([ADR-008](docs/DECISIONS.md)) |
| App Group ID | *(set at M0)* — defined once in a shared constant, never typed twice |
| Minimum iOS | 16 (KeyboardKit 10 requirement) |
| Memory budget | **≤ 40 MB** steady state, against a silent jetsam kill near ~60 MB |
| Network | **None, ever** — no sync, no analytics, no crash reporting ([ADR-005](docs/DECISIONS.md)) |
| Requires | Full Access (for clipboard, haptics, sound) — but **the keyboard always types without it** |

## Build & deploy

*(Fleshed out at M0 once the project exists.)*

1. Open the Xcode project, select the host app scheme, build to the iPhone.
2. First deploy needs a cable + **Developer Mode** on (Settings → Privacy & Security) and the profile trusted (Settings → General → VPN & Device Management). After that, enable "Connect via network" for Wi-Fi deploys.
3. On device: Settings → General → Keyboard → Keyboards → **Add New Keyboard** → the Keyboard Project → tap it → **Allow Full Access**.
4. Settings → *(host app)* → **Paste from Other Apps** → **Allow**. Without this, every clipboard capture fires a system prompt.

**⚠️ The weekly ritual (while on the free account).** Free provisioning profiles expire **7 days** after issuance — the app stops launching and the keyboard dies. Re-deploy from Xcode weekly (~5 min over Wi-Fi). Keep the stock keyboard enabled as a fallback, and set a recurring reminder. This ends at M5 when the $99 program brings 1-year signing / 90-day TestFlight builds.

## Reference links

- **KeyboardKit** — [github.com/KeyboardKit/KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) · [features & free-vs-Pro](https://keyboardkit.com/features) · [releases](https://github.com/KeyboardKit/KeyboardKit/releases)
- **AOSP LatinIME layout XML** — [row_qwerty4.xml](https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/res/xml/row_qwerty4.xml) — the primary source for Gboard's key-width percentages
- **azooKey** — [github.com/azooKey/azooKey](https://github.com/azooKey/azooKey) — MIT, SwiftUI, actively maintained; the modern reference iOS keyboard to study
- **Apple: Creating a custom keyboard** — [developer.apple.com](https://developer.apple.com/documentation/UIKit/creating-a-custom-keyboard) · [Custom Keyboard guide (archive)](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- **Gboard clipboard (Android)** — [support.google.com](https://support.google.com/gboard/answer/10742542) — the behavior being imitated
- **FUTO Swipe** — [swipe.futo.tech](https://swipe.futo.tech/) — the only credible open glide-typing path (v2, [ADR-007](docs/DECISIONS.md))
