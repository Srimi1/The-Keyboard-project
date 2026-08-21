# CONSTRAINTS.md — iOS Platform Facts (the anti-hallucination reference)

> **This document is the ONLY permissible source for iOS platform claims in this project.**
> If a capability, API behavior, limit, or entitlement is not recorded here, do not assert it —
> say **"OPEN QUESTION — needs on-device test"** and add it to the [verification backlog](#10-open-questions--verification-backlog).
>
> **Entry format:** each fact carries → `Source` (URL) · `Recorded` (date) · `Confidence` (high / medium / low) · `Verified on device` (yes / no).
> When a fact is verified on a real device, update its flag and note the device + iOS version.
> New findings: append to the right section using the same format. Never delete a fact — mark it `superseded` with a note.

All facts below recorded **2026-08-21** from the research corpus in [`reference/research-2026-08-21.json`](reference/research-2026-08-21.json) unless noted. None are device-verified yet.

---

## 1. Extension model

- **C-01** — A custom keyboard is an app extension built on a `UIInputViewController` subclass (`NSExtensionPointIdentifier` = `com.apple.keyboard-service`), shipped inside a containing (host) app. The system loads it into *other apps' processes* when the user selects it.
  `Source:` https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html · `Confidence:` high · `Verified:` no
- **C-02** — Each host app gets a fresh `UIInputViewController` instance, and instances/views are retained even after dismissal — per-appearance allocations accumulate (a known leak pattern). Heavy visual effects (gradients, shadows) worsen it. Known mitigations: memory-mapped resources (one documented 52 MB → 27 MB win), emptying heavy views in `deinit` deferred one runloop turn.
  `Source:` https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af · `Confidence:` medium · `Verified:` no
- **C-03** — If the extension crashes or is killed, iOS silently swaps back to the previously used keyboard. The user just sees the keyboard vanish.
  `Source:` same as C-02 · `Confidence:` medium · `Verified:` no
- **C-04** — Data sharing between host app and extension uses **App Groups** (`UserDefaults(suiteName:)` / shared container). See §4 for the Full Access write caveat.
  `Source:` Apple archive guide (C-01) · `Confidence:` high · `Verified:` no

### Project configuration (verified on this machine)

- **C-31** — XcodeGen target type `app-extension` plus a host-app dependency with `embed: true` produces correct embedding: the built `.appex` lands in `KeyboardProject.app/PlugIns/`. Confirmed by inspecting the built bundle.
  `Source:` local build, Xcode 26.6 / XcodeGen 2.45.4 · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes** (macOS build; not yet a device install)
- **C-32** — `NSExtensionPrincipalClass` written as `$(PRODUCT_MODULE_NAME).KeyboardViewController` resolves at build time to the module-qualified name (here `KeyboardExtension.KeyboardViewController`). Confirmed in the built Info.plist. A Swift principal class **must** be module-qualified; a bare class name does not resolve.
  `Source:` local build · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes**
- **C-33** — For **simulator** builds, entitlements are carried in the binary's `__entitlements` section rather than a code signature, so `codesign -d --entitlements -` prints an empty dict even when they applied. With ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) the App Group container *is* reachable in the simulator and a write round-trips. ⚠️ **This is not evidence for Q-01** — the simulator has no provisioning profile, so it exercises the code, not the developer account. Only a real-device run on the free personal team closes Q-01.
  `Source:` local build + run, iOS 26.5 simulator · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes**
- **C-34** — A `TextField` in the **host app** focused while a custom keyboard is active is unremarkable; the documented iOS 17.0–17.1 crash (§8) applies to a text field **inside the keyboard extension**, which this project does not use.
  `Source:` §8 ledger, scoped by reading · `Recorded:` 2026-08-21 · `Confidence:` medium · `Verified:` no
- **C-41** — **Do not read `hasFullAccess` in `viewDidLoad`.** Its sibling `needsInputModeSwitchKey` logs that it "was called before a connection was established to the host application. This will produce an inaccurate result", and in UIKitCore that message is parameterized by selector rather than specific to one property. Apple documents no guarantee either way. Read both in `viewWillAppear`, and re-read on every appearance — **there is no notification or KVO path for Full Access changing**, so polling is the only option.
  `Source:` verification agent against UIKitCore · `Recorded:` 2026-08-21 · `Confidence:` medium · `Verified:` no
- **C-42** — `ENABLE_DEBUG_DYLIB` defaults to **YES** for the app-extension product type in Xcode 16+/26. It is required only for SwiftUI Previews and is a known source of missing `.debug.dylib` load failures, invalid-code-signature errors on the simulator, and missing dSYMs — all of which present as "the keyboard doesn't work" with nothing useful to debug. **Set it to NO on the extension target** (done in `project.yml`); the extension then builds as a single binary.
  `Source:` verification agent + confirmed locally by inspecting the built `.appex` before and after · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes** (build)
- **C-43** — The name shown under Settings → General → Keyboard → Keyboards comes from the **extension** target's `CFBundleDisplayName`, not the app's. Omit it and iOS shows the containing app's `CFBundleName` or an "&lt;App&gt; — &lt;Extension&gt;" compound. Set explicitly (done: "Keyboard Project").
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-44** — The extension's bundle ID **must** be a child of the host app's; the system will not register a keyboard whose ID is not prefixed by its containing app's. Also: sharing source files between the two targets means each compiles its own copy, so `KeyboardProject.Foo` and `KeyboardExtension.Foo` are **different types**. `Codable`/JSON round-trips fine across the boundary (what this project uses); `NSCoding`/`NSKeyedArchiver` embeds the module name and would fail.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no

## 2. Full Access matrix

- **C-05** — Without `RequestsOpenAccess` / Full Access, a keyboard has: **no network, no UIPasteboard, no Location/Contacts, no reliable shared-container access, no audio playback**. Apple's guide lists all of these as open-access-gated.
  `Source:` Apple archive guide (C-01) · `Confidence:` high · `Verified:` no
- **C-06** — `RequestsOpenAccess = true` goes in the extension's Info.plist (`NSExtensionAttributes`). The user must *additionally* toggle **Allow Full Access** in Settings → General → Keyboard → Keyboards → [keyboard]. Check at runtime with `hasFullAccess` (iOS 11+). It is an Info.plist key + user toggle, **not a provisioned entitlement**.
  `Source:` https://shyngys.com/ios-custom-keyboard-guide + Apple archive guide · `Confidence:` high · `Verified:` no
- **C-07** — Haptics: `UIImpactFeedbackGenerator` / `UIFeedbackGenerator` are *callable* in keyboard extensions but **silently no-op without Full Access**. iOS 16's "Keyboard Feedback → Haptic" setting applies only to Apple's system keyboard and did not change extension rules.
  `Source:` https://developer.apple.com/forums/thread/63493 + https://keyboardkit.com/features/feedback + https://9to5mac.com/2022/09/13/ios-16-haptic-feedback-keyboard/ · `Confidence:` medium · `Verified:` no
- **C-08** — Key click sounds: adopt `UIInputViewAudioFeedback` (`enableInputClicksWhenVisible = true`) and call `UIDevice.current.playInputClick()`. Apple's guide lists audio playback under open-access capabilities. Practical keyboards use `AudioServicesPlaySystemSound` (no audio session, respects the silent switch) rather than `AVAudioPlayer` (wrong audio bus in extensions).
  `Source:` Apple archive guide (C-01) + dev.to article (C-02) · `Confidence:` medium · `Verified:` no — see Q-03
- **C-09** — The keyboard **must always still type without Full Access**. This is both a product invariant here and App Review Guideline 4.4.1 (see §9).
  `Source:` https://developer.apple.com/app-store/review/guidelines/ · `Confidence:` high · `Verified:` n/a (policy)

## 3. Memory

- **C-10** — Jetsam kills keyboard extensions at roughly **~60 MB phys_footprint** (measured 63 MB kill on one device; other reports range 30–70 MB by device/OS pressure) — **silently, with no crash log**. **Project budget: ≤ 40 MB steady state.**
  `Source:` dev.to article (C-02) + React Native issue #31910 (~48 MB reports) · `Confidence:` medium · `Verified:` no — see Q-04
- **C-11** — SwiftUI works inside keyboard extensions (KeyboardKit is fully SwiftUI-based), but adds memory overhead against the ceiling.
  `Source:` https://github.com/KeyboardKit/KeyboardKit · `Confidence:` high · `Verified:` no
- **C-36** — **The jetsam ceiling is measurable, not just estimable.** `task_vm_info`'s `limit_bytes_remaining` (struct revision 4+) reports how many bytes this process has left before its own jetsam limit, so `phys_footprint + limit_bytes_remaining` is the **actual ceiling on this device** — which answers Q-04 directly instead of relying on the ~60 MB figure from third-party reports. Caveats: `TASK_VM_INFO_COUNT` **cannot be imported into Swift** (the macro uses `sizeof`; referencing it is a hard compile error) and must be recomputed via `MemoryLayout`; the divisor is `natural_t` but the buffer must be rebound to `integer_t` (`task_info_t == UnsafeMutablePointer<integer_t>`); and `task_info` writes back how many ints it filled — **below revision 1 the `phys_footprint` field is uninitialized garbage rather than an error**, so the returned count must be checked. `limit_bytes_remaining` also stays 0 if the deployment target is below iOS 13 (the kernel gates on `proc_min_sdk`, not the linked SDK); iOS 16 is fine.
  `Source:` verification agent against iOS 26.5 SDK headers, XNU source, and a compiled+executed test · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` partial (compiles and runs; the on-device number is what closes Q-04)

## 4. App Group read/write asymmetry

- **C-12** — Without Full Access, App Group shared-container **reads generally work but writes fail or are unreliable**. Production keyboards mirror preferences in both shared and local defaults with timestamp conflict resolution.
  `Source:` dev.to article (C-02) + https://www.securing.pl/en/third-party-iphone-keyboards-vs-your-ios-application-security/ · `Confidence:` medium · `Verified:` no
- **C-35** — ⚠️ **The App Group false-positive trap.** `UserDefaults(suiteName:)` returns a **non-nil** instance for a group the process is *not* entitled to, and an in-process write/read-back **succeeds off the in-process cache**. `synchronize()` also returns true for a bogus suite. So a diagnostics check built that way reports a pass on a completely unprovisioned group. **The reliable entitlement signal is `FileManager.containerURL(forSecurityApplicationGroupIdentifier:) == nil`** (iOS processes are always sandboxed). Proof the group is genuinely *shared* requires a **cross-process token** — one process writes, the other reads.
  `Source:` verification agent against iOS 26.5 SDK headers + empirical test · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no (design applied in `AppGroup.probeAvailability`)

## 5. Pasteboard privacy (the clipboard manager's rulebook)

- **C-13** — **iOS has no background clipboard monitoring for third parties. Period.** Clipboard-history apps (Paste, ClipBox, PastePal) capture only when their code runs: keyboard extension open (read + poll while visible), main app foregrounded, or share/action extensions. Items copied between openings — beyond the most recent — are unrecoverable.
  `Source:` https://pasteapp.io/help/paste-on-iphone · `Confidence:` high · `Verified:` no
- **C-14** — Since iOS 16, reading UIPasteboard *values* (`string`, `strings`, …) from another app triggers the system **"Allow Paste"** alert. Since iOS 16.1, each app has Settings → [App] → **"Paste from Other Apps"** (Ask / Deny / Allow) to suppress it permanently.
  `Source:` https://sarunw.com/posts/uipasteboard-privacy-change-ios16/ + https://www.ithinkdiff.com/why-do-you-see-the-allow-paste-prompt-in-ios-16/ · `Confidence:` high · `Verified:` no
- **C-15** — "Paste from Other Apps = Allow" on the **containing app covers its keyboard extension too** (Paste's docs: granting it lets "both Paste and Paste Keyboard" access the clipboard without per-read prompts). Confirmed via Paste through iOS 17/18 docs; re-test on the installed iOS version.
  `Source:` https://pasteapp.io/help/allow-paste-permissions-in-ios · `Confidence:` high · `Verified:` no — see Q-05
- **C-16** — `UIPasteboard.changeCount`, `hasStrings` / `hasURLs` / `hasImages`, and `detectPatterns(for:)` (iOS 14+) **do NOT trigger the paste prompt**; only exposing actual values does. Prompt-free change detection is therefore free while the keyboard is visible.
  `Source:` sarunw.com (C-14) + https://sentinelden.com/blog/pasteboard-detection-without-banner/ · `Confidence:` medium · `Verified:` no
- **C-17** — Gboard for iOS does **not** include Android Gboard's clipboard-history feature; Apple's stock keyboard has none either; iOS holds a single system-wide clipboard item. (This project's clipboard manager exceeds anything available on iOS.)
  `Source:` https://support.google.com/websearch/thread/105849467 + https://clipboardai.app/blog/articles/iphone-vs-android-clipboard-war · `Confidence:` high (medium for the Gboard-iOS specifics) · `Verified:` no
- **C-37** — **A fast `nil` from a pasteboard read is ambiguous.** "Paste from Other Apps = **Deny**" returns nil *quickly and with no prompt* — indistinguishable from an empty pasteboard unless the prompt-free `hasStrings` is checked first. Interpretation: slow → prompt appeared; fast + value → allowed; fast + nil + `hasStrings` → **Deny**; fast + nil + no strings → genuinely empty.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-38** — **The pasteboard read blocks the calling thread while the alert is displayed.** On the main thread in a keyboard extension this visibly freezes the keyboard for as long as the user takes to tap. Chromium moved this off the main thread for exactly this reason. → M3's capture pipeline must not read on the main thread.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-39** — Without Full Access the extension cannot reach the general pasteboard **at all** — the sandbox denies the connection. Ungated pasteboard diagnostics therefore report a confusing "empty" instead of a clear "blocked".
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-40** — API naming traps: `detectPatterns(for:completionHandler:)` is **deprecated since iOS 15**; the current async spelling is `detectedPatterns` (past tense). `detectValues` / `detectedValues` **do trigger the prompt** even though the `Patterns` variants do not — one character apart, opposite privacy consequence. `UIPasteboard.pasteboardTypes` does not exist in Swift; it is `types`.
  `Source:` verification agent against the UIKit Swift overlay · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no

## 6. Text APIs

- **C-18** — `textDocumentProxy` verbs: `insertText`, `deleteBackward`, `adjustTextPosition(byCharacterOffset:)`. `documentContextBeforeInput` / `AfterInput` return **only nearby context** (observed ≈ the last two sentences / up to sentence-paragraph boundaries) — never the full document. "Full document context" requires cursor-moving hacks (what KeyboardKit Pro's `fullDocumentContext()` does), which are inherently fragile.
  `Source:` https://developer.apple.com/forums/thread/772158 + https://keyboardkit.com/features/proxy-utilities · `Confidence:` medium · `Verified:` no
- **C-19** — Custom keyboards get **no access to the system autocorrect/QuickType engine**. Available primitives: `UITextChecker` (misspelled-range, guesses, completions) and `requestSupplementaryLexicon` (`UILexicon`: unpaired contact names + Settings text replacements + common words). Both work **without** Full Access. Third-party keyboards implement autocorrect themselves — this is why they feel worse than stock.
  `Source:` Apple archive guide (C-01) + https://developer.apple.com/documentation/uikit/uiinputviewcontroller/requestsupplementarylexicon(completion:) + https://nshipster.com/uitextchecker/ · `Confidence:` high · `Verified:` no
- **C-20** — Custom keyboards are automatically replaced by the system keyboard in `secureTextEntry` (password) fields and phone-pad keyboard types. Any host app can ban all third-party keyboards via `shouldAllowExtensionPointIdentifier` (common in banking apps). **Not fixable — do not burn time on it.**
  `Source:` Apple archive guide (C-01) · `Confidence:` high · `Verified:` no

## 7. UI constraints

- **C-21** — Globe key: show one **only if `needsInputModeSwitchKey` is true** — it is *false* on Face ID iPhones, where the system draws globe/dictation keys below the keyboard. Wire it to `advanceToNextInputMode()` / `handleInputModeList(from:with:)`. You cannot choose which keyboard comes next.
  `Source:` https://developer.apple.com/documentation/uikit/uiinputviewcontroller/needsinputmodeswitchkey + forum threads 92030/90937 · `Confidence:` high · `Verified:` no
- **C-22** — Keyboard height is customizable via a height `NSLayoutConstraint` on the input view (width is always system-set). It only takes effect after the view first draws; wrong-initial-height / resize-flicker issues persist into iOS 18/26 (view sized 0×0 → fullscreen → settling), and host apps sometimes miss frame-change notifications for taller keyboards.
  `Source:` https://developer.apple.com/forums/thread/813579 + https://github.com/DimaVartanian/keyboard-extension-height-bug · `Confidence:` medium · `Verified:` no
- **C-45** — **Intrinsic sizing does not work for keyboard height — at all.** `UIInputView.allowsSelfSizing`, `intrinsicContentSize` overrides, `preferredContentSize`, frame/bounds overrides, and forcing `layoutSubviews` are **all ignored** by the keyboard host process. Only an `NSLayoutConstraint` on `self.view` works, and only after first draw. Give it priority **999**, not required — at required it conflicts with the system's own `UIView-Encapsulated-Layout-Height` and spams constraint-breakage logs. The 0×0 → fullscreen → settling flicker is **unavoidable by supported means (confirmed by Apple DTS)** — apply the `viewIsAppearing` offset workaround and move on rather than burning days on it.
  `Source:` verification agent against UIKit headers + Apple DTS threads · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-46** — `UIHostingController` adds a **bottom safe-area inset that `.ignoresSafeArea()` inside the SwiftUI view cannot remove**. The only fix is `hostingController.safeAreaRegions = []`, which is **iOS 16.4+** — at a 16.0 deployment target it needs an availability guard. Relatedly, the iOS 26 transparent-background rule must be applied to **all three** layers: `self.view`, `inputView`, and the hosting controller's view.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes** (applied in `KeyboardViewController`)
- **C-47** — **The globe key must be a real `UIButton`** with a target for **`.allTouchEvents`** calling `handleInputModeList(from:with:)`. A SwiftUI `Button` calling `advanceToNextInputMode()` handles only tap and **silently loses the touch-and-hold keyboard picker** — App Review has rejected keyboards for exactly this.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` **yes** (applied via `NextKeyboardButton`)
- **C-48** — Opening the containing app: only SwiftUI `Link` / `openURL` works, and the URL scheme must be declared in the **host app's** Info.plist, not the extension's. `extensionContext?.open` compiles but is Today-widget-only. Separately, **there is no supported way for a keyboard extension to learn the host app's bundle ID**, so "deep-link out and come back" UX cannot be built with public API.
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` high · `Verified:` no
- **C-49** — SwiftUI `TextField` / `TextEditor` **inside a keyboard extension** is a known memory blow-up against the jetsam ceiling — avoid entirely. Also: `UIInputViewController` never releases its view, so the SwiftUI hierarchy must be built **once**, and the hosting controller's `rootView` must not strongly capture the input view controller (a retain cycle keeps the whole SwiftUI graph alive across every host app).
  `Source:` verification agent · `Recorded:` 2026-08-21 · `Confidence:` medium · `Verified:` no

## 8. OS-gotcha ledger (dated — consult before proposing platform code)

| iOS / tool | Gotcha | Source | Confidence |
|---|---|---|---|
| iOS 17.0–17.1 | Focusing a text field *inside* a keyboard extension crashed when Full Access was off (fixed ~17.2) | https://keyboardkit.com/blog/2023/11/13/text-input-crashes-in-ios17 | medium |
| iOS 17.1 | Extension launch crashes in production, fixed by 17.2 | https://keyboardkit.com/blog/2023/12/10/critical-extension-crashes-in-ios-17-1 | medium |
| iOS 17.2–17.3.1 | Keyboards whose extension bundle-ID segment starts with `se` disappeared from Settings (earlier: `mn.` on iOS 13) → **use `com.<name>.*` reverse-DNS bundle IDs, always** | https://developer.apple.com/forums/thread/746530 + thread/121542 | medium |
| iOS 18 / Xcode 16 | Multi-gesture buttons inside scroll views broke (emoji-grid pain); gesture rewrites required | https://keyboardkit.com/blog/2024/09/06/xcode16-breaks-emoji-keyboard-gestures-in-ios18 | high |
| iOS 18 | Killed the responder-chain/selector-based `UIApplication.openURL` trick for opening the host app → **use SwiftUI `Link`** | https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening | high |
| iOS 26 (Liquid Glass) | System wraps keyboards in a rounded-glass background container in adopting apps; opaque keyboard backgrounds render as a gray bar/frame → **use transparent backgrounds**. Native key metrics (heights/insets/font weights) also changed. No new extension APIs. | https://keyboardkit.com/blog/2025/07/28/custom-ios-keyboard-extensions-and-liquid-glass + forum thread 793686 | medium |
| iOS 26.4 | Host-app bundle-ID access changed (old private `_hostBundleID` paths return nil; KeyboardKit 10.6.1 restored a `hostApplicationBundleId` working only on 26.4+) | https://developer.apple.com/forums/thread/826851 | medium |

## 9. Accounts, provisioning & App Review

- **C-23** — **Free personal team**: provisioning profiles expire **7 days** from issuance (the app stops launching until re-deployed from Xcode); max **10 App IDs** at a time / per 7 days (**host app + keyboard extension consume 2**); 10 App ID capability changes per 7 days; **3 test devices** per platform; ~3 development apps installed per device; no TestFlight/App Store.
  `Source:` https://developer.apple.com/support/compare-memberships/ + https://faq.altstore.io/altstore-classic/app-ids · `Confidence:` high · `Verified:` no
- **C-24** — Keyboard extensions **build and run with free provisioning**: the keyboard extension point needs no paid-only entitlement, and Full Access is an Info.plist key + user toggle (C-06), not a provisioning entitlement.
  `Source:` https://developer.apple.com/documentation/UIKit/creating-a-custom-keyboard + Apple archive guide · `Confidence:` high · `Verified:` no
- **C-25** — **App Groups is available to free personal-team accounts on iOS** per Apple's "Supported capabilities (iOS)" table, corroborated by the LoopKit community building App-Group-using apps on free accounts (removing only Push Notifications, Siri, NFC, Time Sensitive Notifications — which ARE paid-only). ⚠️ One research thread flagged a conflict — **M0 empirical test required** (Q-01); if it fails, buy the $99 program immediately.
  `Source:` https://developer.apple.com/help/account/reference/supported-capabilities-ios/ + https://loopkit.github.io/loopdocs/build/build-free-loop/ · `Confidence:` high (with flagged conflict) · `Verified:` no
- **C-26** — **Developer Mode** (Settings → Privacy & Security, iOS 16+) is required for any development-signed install (Xcode, AltStore/SideStore). TestFlight and App Store apps don't need it.
  `Source:` https://developer.apple.com/videos/play/wwdc2022/110344/ · `Confidence:` high · `Verified:` no
- **C-27** — **Paid $99/yr program**: development provisioning lasts 1 year; 100 devices/type/year; ad-hoc distribution; TestFlight builds expire after 90 days with up to 100 internal testers (no review; external testers need Beta App Review). App Groups + keyboard extension + Full Access all work identically.
  `Source:` https://developer.apple.com/support/compare-memberships/ + https://appcircle.io/guides/ios/ios-app-distribution · `Confidence:` high · `Verified:` no
- **C-28** — **AltStore/SideStore** inherit the same free-account limits (7-day, 3 apps, 10 App IDs) and add background re-signing. They prompt to keep or strip extensions (stripped = no keyboard at all; the prompt historically failed for source-downloaded apps), and they **rewrite app-group identifiers per signing account** — a specific breakage risk for a hardcoded group string. No first-hand reports confirm keyboards work end-to-end this way. **Rejected as the path** (ADR-004).
  `Source:` https://docs.sidestore.io/docs/faq + https://github.com/rileytestut/AltStore/issues/929 + https://github.com/SideStore/SideStore/issues/68 · `Confidence:` high/medium · `Verified:` no
- **C-29** — After one cable deploy + device trust, Xcode supports **Wi-Fi deployment** ("Connect via network"); the weekly free-account ritual is ~2–5 minutes at the Mac. If the profile lapses away from the Mac, the keyboard is dead until you return.
  `Source:` LoopDocs + standard Xcode behavior (not re-verified against a primary doc) · `Confidence:` medium · `Verified:` no
- **C-30** — App Review rules, recorded for a **hypothetical future** public release (v1 is personal-use only): **4.4** — host apps containing extensions must include real functionality (help screens, settings); extensions may not contain marketing/ads/IAP. **4.4.1** — keyboards must provide actual typed input, provide a next-keyboard method, remain functional without network and without Full Access, collect user activity only to enhance keyboard functionality, never launch other apps besides Settings, never repurpose keys. **5.1.1** — privacy policy link in-app and in App Store Connect. **5.1.2** — no using collected data to build user profiles.
  `Source:` https://developer.apple.com/app-store/review/guidelines/ · `Confidence:` high · `Verified:` n/a (policy)

## 10. Open questions / verification backlog

Each has a test procedure; record the verdict here **and** flip the relevant fact's `Verified` flag.

| ID | Question | How to test | Verdict |
|---|---|---|---|
| **Q-01** | Does App Groups actually provision on a free personal team for a keyboard-extension + host-app pair on current Xcode/iOS? (C-25 conflict) | M0: add App Groups capability to both targets on the free team; with Full Access ON, write from the extension, read from the host app. If it fails → buy $99 program that day. | — |
| **Q-02** | Does KeyboardKit 10's binary do any network license validation from inside the extension? (fatal in a no-network context) | M0 spike: run the free tier in the extension with device in Airplane Mode; watch for stalls/failures; check network logs. | — |
| **Q-03** | Does `UIDevice.playInputClick` strictly require Full Access on current iOS, or does it work without? (C-08) | Toggle Full Access off; tap keys; listen. | — |
| **Q-04** | Exact jetsam ceiling on the target device/iOS. (C-10) | Instruments; allocate in steps; record phys_footprint at kill. | — |
| **Q-05** | Does "Paste from Other Apps = Allow" fully suppress paste prompts for **extension-process** reads on the installed iOS version? What attribution does the alert show? (C-14/C-15) | M0/M3: set Allow on host app; read pasteboard from extension; observe. If prompts persist → fall back to explicit tap-to-capture. | — |
| **Q-06** | Exact truncation rules of `documentContextBeforeInput` per field type / host app. (C-18) | Log lengths across Notes, Messages, Safari fields. | — |
| **Q-07** | Can the extension detect iOS 26's Liquid Glass wrapper at runtime to conditionally style? | Probe view hierarchy / trait environment on device; forum posters had found no reliable check. | — |
| **Q-08** | KeyboardKit 10 free-tier locale-layout coverage beyond English (relevant only if English-only decision is ever revisited). | Hands-on test of the free SDK. | — |
| **Q-09** | Do pasteboard `localOnly` / expiration hints from password managers reach the extension, and are they respected by our capture? (privacy) | Copy from a password manager; inspect item metadata in the capture pipeline. | — |

---

*Related docs: [ARCHITECTURE.md](ARCHITECTURE.md) (how these constraints shape the design) · [CLIPBOARD.md](CLIPBOARD.md) (pasteboard rules applied) · [DECISIONS.md](DECISIONS.md) (choices these facts forced) · [ROADMAP.md](ROADMAP.md) (M0 runs the verification backlog).*
