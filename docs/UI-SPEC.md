# UI-SPEC.md — The Gboard layout blueprint

> **This is the visual and interaction authority.** Build from these numbers and tables, not from memory of what a keyboard looks like.
>
> **Two kinds of entries appear here:**
> - **Sourced values** — from AOSP LatinIME (Gboard's open-source visual ancestor, the closest primary source to Gboard's closed-source metrics) or Google's own documentation.
> - **📐 MEASURE** — a value that must be measured from screenshots of a real Android device running Gboard before it is implemented. **Do not guess these. Do not let a placeholder ship as if it were verified.**
>
> Reference: Gboard for **Android** (ADR-001). When in doubt about a behavior, the answer is "whatever Gboard-Android does" — and if nobody knows, it's a 📐 MEASURE item.

---

## 1. Layout grid

All widths are **percentages of keyboard width**, which is how AOSP defines them — this makes the layout resolution- and device-independent, and the width is always system-set (C-22).

**Row 1 — 10 keys, no inset**
```
│ q │ w │ e │ r │ t │ y │ u │ i │ o │ p │      each 10%
```

**Row 2 — 9 keys, centered with a half-key (5%) inset each side**
```
  │ a │ s │ d │ f │ g │ h │ j │ k │ l │        each 10%, 5% gap at both ends
```

**Row 3 — shift + 7 letters + backspace**
```
│  ⇧  │ z │ x │ c │ v │ b │ n │ m │  ⌫  │      shift 15%, letters 10%, backspace 15%
```

**Row 4 — the function row (this is the row iPhone users notice is wrong)**
```
│ ?123 │ , │        space "English (US)"        │ . │ return │
    15%   10%                  ~50%                 10%   ~15%
```

Sourced: AOSP LatinIME `row_qwerty4.xml` — letter keys 10%, shift/delete 15%, symbols key 15%, comma 10%, spacebar starting at x=25% (~50% wide), period 10%, enter filling the right (~15%).
`Source:` https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/java/res/xml/row_qwerty4.xml

**Globe key insertion.** Show a globe key **only when `needsInputModeSwitchKey` is true** (C-21). Do not infer that value from the device class: it measured `true` on an iPhone 14 with iOS 26.5, while verification on the current target iPhone remains open. When true, it takes the comma's slot and the comma moves into the period's long-press set. 📐 MEASURE every supported device/OS combination.

**📐 MEASURE list for §1:** exact key **heights** per row, **horizontal/vertical gaps** between keys, **corner radius**, keyboard **total height** per device class, and whether Gboard's spacebar is exactly 50% or slightly different in its current build.

## 2. Layers

Five layers. Layer-switch keys always occupy the `?123` slot position.

| Layer | Entered by | Layer key shows | Notes |
|---|---|---|---|
| **base** | default | `?123` | lowercase letters |
| **shifted** | tap ⇧ | `?123` | one capital, then auto-returns to base |
| **caps-lock** | double-tap ⇧ | `?123` | persists until ⇧ tapped; distinct ⇧ visual (filled/underlined) |
| **symbols `?123`** | tap `?123` | `ABC` | digits row + common punctuation |
| **extended `=\<`** | tap `=\<` inside symbols | `ABC` | maths/currency/rare symbols |

**📐 MEASURE:** the exact key contents and arrangement of the `?123` and `=\<` layers in current Gboard, and which layer the `=\<` key sits in. Capture both layers before Phase 3 owner acceptance.

## 3. Key states & touch behavior

| State | Behavior |
|---|---|
| **Idle** | Letter keys and function keys use different fills (§9) |
| **Pressed** | Key darkens/highlights **and** the preview popup appears (§4) |
| **Slide-off** | Dragging off a pressed key and releasing **cancels** — no character inserted |
| **Multi-touch rollover** | Pressing a second key before releasing the first commits the first, then the second — fast typists rely on this |
| **Repeat** | Only backspace repeats on hold (§6) |

## 4. Key-preview popup

Gboard's "Popup on keypress" (on by default on Android): an enlarged copy of the character appears **above** the pressed key.

- Not shown for spacebar, shift, backspace, return, or layer keys — letters and punctuation only.
- On the top row (no space above), the popup renders above the keyboard's top edge, overlapping the suggestion strip.
- **📐 MEASURE:** popup size relative to the key, offset above it, corner radius, and appear/dismiss animation timing.

## 5. Long-press map

Long-press is where muscle memory lives, and where iOS keyboards feel most wrong to an Android user. Three distinct long-press systems:

### 5a. Letter keys → accent callouts

Hold a letter, a horizontal callout row appears, slide to choose, release to insert. **Sourced from AOSP LatinIME**, not a guess: `tools/make-keyboard-text/res/values-en/donottranslate-more-keys.xml` (fetched 2026-08-21, `master` branch) — the English-locale override of the code-generation tool's `donottranslate-more-keys.xml`, whose `values/` base defines every `morekeys_*` string empty. English overrides exactly **eight** letters; everything else has none, notably `y`, `d`, `g`, `l`, `z` — a plausible-looking guess would have given those ÿ, ď, ğ, ł, ž, and been wrong.

| Key | Alternates | | Key | Alternates |
|---|---|---|---|---|
| `a` | à á â ä æ ã å ā | | `s` | ß |
| `e` | é è ê ë ē | | `c` | ç |
| `i` | í î ï ī ì | | `n` | ñ |
| `o` | ó ô ö ò œ ø ō õ | | *others* | no alternates |
| `u` | ú û ü ù ū | | | |

This is AOSP LatinIME's table, the best available open-source proxy — Gboard itself is closed-source and may differ. V-05 in §12 still covers confirming it against a real device.

### 5b. Top row → digit hints (Gboard's "Long press for symbols")

Small **corner hint glyphs** render on the top-row keys; long-press inserts the digit:

```
 q¹  w²  e³  r⁴  t⁵  y⁶  u⁷  i⁸  o⁹  p⁰
```

This is a v1 requirement — it's how Gboard users type numbers without a number row (which is off by default on Android). 📐 MEASURE the hint glyph size, position, and opacity.

### 5c. Punctuation keys

- **Period `.`** → an **8-column, 2-row grid** of 16 symbols (`morekeys_punctuation`, `!autoColumnOrder!8` — fixed column count, automatic placement). **Sourced from AOSP** (same file as §5a). AOSP fills the row nearest the touch point first, so the resource order lays out bottom-row-then-top-row, left to right:
  - Bottom row (closest to the held key): `, ? ! # ) ( / ;`
  - Top row: `' @ : - " + % &`

  This supersedes the earlier press-coverage guess (`& % + # ! @ ? ( )`), which had both the wrong membership and no ordering. 📐 Cell size, spacing, and corner radius still need a device screenshot — V-06 in §12 now covers styling only.
- **Comma `,`** → no special long-press action in v1. Keyboard preferences are available
  from the dedicated settings button in the toolbar. The extension never attempts to launch
  the host app; one-handed mode remains deferred. The Gboard comma popup remains a visual
  reference for a later, policy-compliant interaction.
- **Spacebar long-press** → language switch on Android. English-only in v1 (ADR-002), so v1 has no separate long-press action. Horizontal sliding remains cursor movement (§6).

## 6. Gestures

| Gesture | Behavior | Notes |
|---|---|---|
| **Spacebar slide L/R** | Moves the text cursor one character per threshold crossed, via `adjustTextPosition(byCharacterOffset:)` | Gboard-iOS does left/right only (no up/down). 📐 MEASURE the pixel threshold per character step and whether it accelerates. |
| **Double-space** | Inserts `. ` (period + space), replacing the first space | 📐 MEASURE the timing window. Immediate backspace must revert to two spaces. |
| **Backspace hold** | Deletes character-by-character, then accelerates to two characters per repeat | 📐 MEASURE initial delay, repeat interval, and the acceleration curve. Word-level gesture deletion remains deferred. |
| **Slide-off any key** | Cancels the keypress | §3 |
| **Backspace slide-left** | *(gesture delete — deferred, ADR-007)* | Do not implement in v1 |
| **Glide typing** | *(deferred to v2, ADR-007)* | Do not implement in v1 |

## 7. Toolbar

The 44-point strip above the keys is active in v1. It contains two fixed controls:
**clipboard** and **settings**. It has no customization or expansion panel. Debug builds may
also show development diagnostics; those controls compile out of Release.

After an explicit, successful **Save current clipboard** action, a pill-shaped paste chip
shows a shortened preview. Tapping it inserts the saved text if it is still valid. Typing,
moving the cursor, changing panels, revoking Full Access or dismissing the keyboard cancels a
pending insertion and/or dismisses the chip as appropriate. Opening or foregrounding the app
or keyboard never detects or reads clipboard values.

A three-candidate suggestions/autocorrect state is post-v1 work (ADR-014). Its eventual
design must always leave the literal typed text reachable, but it is not part of the current
release contract.

## 8. Clipboard panel

The clipboard button replaces the **key area** (not the whole keyboard) with the panel; the strip stays visible.

```
┌─────────────────────────────────────┐
│  ← back        Clipboard        ✎   │   header: back, title, edit (v1.x)
├─────────────────────────────────────┤
│  PINNED                             │
│  ┌────────────┐ ┌────────────┐      │   item cells:
│  │ 📌 text…   │ │ 📌 text…   │      │   • text preview (truncated)
│  └────────────┘ └────────────┘      │   • age ("2 min ago") for recents
│  RECENT                             │   • pin indicator
│  ┌────────────┐ ┌────────────┐      │
│  │ text…      │ │ text…      │      │   tap        → insert at cursor
│  └────────────┘ └────────────┘      │   long-press → pin / delete menu
└─────────────────────────────────────┘
```

**Required states:** populated, **empty** ("Save text to keep it here"), and **no Full
Access**. The unavailable state explains how to enable access in Settings without attempting
to launch the host app. Full behavior is in [CLIPBOARD.md](CLIPBOARD.md).

📐 MEASURE the Gboard panel's cell size, columns, section headers, and scrolling behavior.

## 9. Theming

The theme system is token-driven: every letter key, function key, pressed state, popup,
toolbar control, clipboard card and settings surface resolves from the same active
`KeyboardTheme`. Individual keys never receive one-off colors.

| Role | Light | Black | Neon |
|---|---|---|---|
| Canvas | `#F6F8FB → #E8EDF3` | `#050506 → #111318` | `#050611 → #0B1020` |
| Letter key | `#FFFFFF → #F8FAFC` | `#252830 → #15171C` | `#172A40 → #091222` |
| Function key | `#E8EDF2 → #D5DCE4` | `#181A20 → #090A0D` | `#2A1450 → #10091F` |
| Label | `#111827` | `#F8FAFC` | `#F4FBFF` |
| Hint | `#64748B` | `#A3ACBA` | `#7ADFFF` |
| Accent | `#2563EB` | `#55D6FF` | `#00F0FF` |
| Border | `#C9D2DC` | `#373B45` | `#7C4DFF` |

**System** follows iOS and resolves to Light or Black. The old persisted `dark` value now
displays as Black, so installed users keep their preference. Neon uses a 1.6-point shallow
cyan glow; larger per-key blur is intentionally prohibited until device profiling proves it
fits the extension budget. Exact tokens and icon semantics are mirrored in `assets/themes/`.

Function icons use a single monoline SF Symbols vocabulary. Dynamic return actions such as
Send/Search remain text so the field's requested action is never hidden behind a generic icon.

**⚠️ iOS 26 Liquid Glass rule (hard constraint).** The keyboard background must be **transparent** — iOS 26 wraps keyboards in a system rounded-glass container, and an opaque background renders as a gray bar/frame (CONSTRAINTS §8 gotcha ledger). The palette's "keyboard background" value therefore applies to the *fallback*, not as an unconditional opaque fill. Never paint an opaque full-bleed background.

## 10. Feedback

| Event | Haptic | Sound |
|---|---|---|
| Letter key | light impact | key click |
| Function key (⇧, layer, return) | light impact | key click (📐 verify Gboard differentiates) |
| Backspace (each repeat) | light impact, possibly suppressed during fast repeat | click, 📐 verify suppression |
| Long-press callout open | selection change | none |

Both haptics and sound **no-op without Full Access** (C-07, C-08) — feature-gate on `hasFullAccess`. Use `UIDevice.current.playInputClick()`, not `AVAudioPlayer` (wrong audio bus in extensions, C-08), paired with a `UIInputViewAudioFeedback` conformance on the `UIInputView` itself, not the controller (C-50). Without Full Access, `playInputClick` has also been reported to hang rather than no-op silently (C-51) — the `hasFullAccess` gate is mandatory, not optional hygiene.

## 11. Keyboard height

Set via a height `NSLayoutConstraint` on the input view; width is always system-set (C-22).

**Known constraint:** the constraint only takes effect after first draw, and wrong-initial-height / resize flicker persists into iOS 18/26 (view sized 0×0 → fullscreen → settling). The current implementation applies a priority-999 height constraint after first draw and recalculates after layout/rotation. Phase 3 must still verify the result on each target; code inspection does not close the visual/flicker gate.

📐 MEASURE Gboard-Android's height as a fraction of screen height on a comparable device, and pick the iPhone equivalent that preserves key aspect ratio.

## 12. Open visual questions (the 📐 MEASURE backlog)

Capture these from the owner's real Android Gboard setup before **Phase 3 owner acceptance**. Until they are supplied and compared, the candidate can be functionally tested but its visual match is not approved.

| # | What to capture | Needed by |
|---|---|---|
| V-01 | Full keyboard, light + dark, both key-border settings | Phase 3 |
| V-02 | Exact key heights, gaps, corner radii (measured in pixels, with device DPI noted) | Phase 3 |
| V-03 | `?123` and `=\<` layers, complete | Phase 3 |
| V-04 | Key-preview popup mid-press (size, offset, radius) | Phase 3 |
| V-05 | Accent callout row open on `e`, `a`, `o` — **sets sourced from AOSP (2026-08-21); this now confirms callout styling only** | Phase 3 |
| V-06 | Period long-press grid — **contents and ordering sourced from AOSP (2026-08-21); this now confirms cell size/spacing/corner radius only** | Phase 3 |
| V-07 | Comma-key geometry; long-press popup is deferred | Post-v1 |
| V-08 | Top-row digit hint glyphs (size, position, opacity) | Phase 3 |
| V-09 | v1 clipboard/settings toolbar and post-save paste chip | Phase 3 |
| V-10 | Clipboard panel: populated, empty, with pinned items | Phase 3 |
| V-11 | Keyboard total height vs. screen, portrait | Phase 3 |

---

*Related docs: [PRODUCT.md](PRODUCT.md) (what's in v1) · [CLIPBOARD.md](CLIPBOARD.md) (panel behavior in full) · [CONSTRAINTS.md](CONSTRAINTS.md) (the platform limits cited here) · [ARCHITECTURE.md](ARCHITECTURE.md) (how this gets built) · [ROADMAP.md](ROADMAP.md) (Phase 3 owns reference comparison and owner acceptance).*
