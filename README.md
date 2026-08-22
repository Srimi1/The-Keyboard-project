<div align="center">

<img src="docs/assets/app_icon.png" width="128" height="128" alt="The Keyboard Project Icon" style="border-radius: 28px; margin-bottom: 8px; box-shadow: 0 12px 32px rgba(0,0,0,0.4);" />

# The Keyboard Project

**An iPhone keyboard engineered with the authentic Android Gboard layout, tactile feel, and multi-item clipboard history.**  
*Native Swift & SwiftUI • 100% Offline Privacy • Jetsam-Safe (≤40MB) • AOSP Key Geometry*

[![iOS](https://img.shields.io/badge/iOS-16.0%2B%20%7C%2017%20%7C%2018%20%7C%2026-black?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Srimi1/The-Keyboard-project)
[![Swift](https://img.shields.io/badge/Swift-5.0%20%7C%206.0-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://github.com/Srimi1/The-Keyboard-project)
[![Memory Budget](https://img.shields.io/badge/Memory-%E2%89%A440MB%20Jetsam--Safe-34C759?style=for-the-badge)](docs/CONSTRAINTS.md)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline-00C7BE?style=for-the-badge)](SECURITY.md)
[![License](https://img.shields.io/badge/License-MIT-007AFF.svg?style=for-the-badge)](LICENSE)
[![Release](https://img.shields.io/badge/Release-v0.1.0%20(Alpha)-FF9500?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Srimi1/The-Keyboard-project/releases)

[**📱 Setup Guide**](#-deploying-to-an-iphone) • [**⚡ Quick Start**](#-quick-start) • [**📋 Clipboard Architecture**](docs/CLIPBOARD.md) • [**📐 UI Specification**](docs/UI-SPEC.md) • [**Release Notes**](CHANGELOG.md) • [**ADR Decisions**](docs/DECISIONS.md)

</div>

---

> [!TIP]
> **🚀 The Keyboard Project Alpha Launch**: Built natively to replicate the Android Gboard layout and persistent multi-item clipboard history on iOS — zero cloud tracking, zero network permissions, and strictly under 40 MB physical memory.

---

## ✨ Overview

Switching from Android to iPhone costs you two essential daily workflows:

1. **The Layout & Muscle Memory:** Gboard's dedicated punctuation row, key proportions, symbol positions, and long-press maps.
2. **The Multi-Item Clipboard:** Android's Gboard maintains a persistent history of copied text, links, and snippets. iOS keeps exactly **one** item at a time, overwriting history instantly.

Google abandoned development of Gboard for iOS at **v2.3.19 (May 2022)**, and Apple's native keyboard has no clipboard manager.

**The Keyboard Project** fixes this with a clean, privacy-first, zero-network custom keyboard extension built natively in Swift for iOS.

---

## 🏆 Engineering Milestones & Progress Ledger

| Milestone | Status | Key Deliverables & Achievements |
| :--- | :---: | :--- |
| **M0 — Feasibility Spike** | ✅ **Done** | Verified cross-process App Groups on a free personal developer team (iPhone 14 / iOS 26.5). Built non-intrusive pasteboard IPC probe and memory diagnostic harness. |
| **M1 — Typeable QWERTY** | ✅ **Done** | Built base QWERTY layout matching AOSP LatinIME key-width percentages (10% letter keys, centered row 2 inset, dedicated Gboard function row `[?123][,][space][.][return]`). Shipped 52 unit tests. |
| **M2 — Gboard Feel** | ✅ **Done** | Implemented AOSP more-keys accent callouts, native haptic feedback, click sounds (gated on Full Access), and custom `MultiTouchView` tracker with rollover and hold-to-repeat backspace. Shipped 19 XCUITest touch trials. |
| **Release Trimming & Polish** | ✅ **Done** | Stripped development harness out of Release builds (zero timers and zero background I/O while typing). Added Apple Privacy Manifest (`NSPrivacyTracking: false`), official **3-Row Horizon** app icon, and GitHub Actions CI/CD automation. |
| **M3 — Clipboard Manager** | 🚧 *Next* | Multi-item capture pipeline, deduplication, pinning, and inline panel UI. |
| **M4 — Autocorrect & Strip** | ⬜ *Planned* | 3-slot candidate suggestion strip powered by local Apple NLP engine. |

---

## ⚡ Key Features

- ⌨️ **Accurate Gboard Geometry:** Key-width percentages sourced directly from AOSP LatinIME specifications (10% letter width, centered second row, Gboard function row).
- 📋 **Persistent Multi-Item Clipboard:** Captures and stores your copy history securely in an isolated App Group container on your device (M3).
- 🔒 **100% Offline & Private:** **Zero network capability.** What you type stays on your physical hardware ([ADR-005](docs/DECISIONS.md)).
- ⚡ **Lightweight & Jetsam-Safe:** Runs within a **≤ 40 MB memory budget**. The shipping extension runs **no timers and no per-appearance disk I/O** in Release builds.
- 📳 **Tactile Feedback:** Native iOS system haptic responses and system click audio matching physical keypresses.
- 🛡️ **Graceful Degradation:** The keyboard is guaranteed to type text even if Full Access is turned off ([ADR-001](docs/DECISIONS.md)).

---

## 📊 Comparison Matrix

| Feature | iOS Stock Keyboard | Gboard for iOS *(Frozen 2022)* | **The Keyboard Project** |
| :--- | :---: | :---: | :---: |
| **Android Gboard Layout** | ❌ | ⚠️ Partial | ✅ **1:1 AOSP Specs** |
| **Multi-Item Clipboard History** | ❌ | ❌ | ✅ **Full History** |
| **Zero Network / 100% Offline** | ⚠️ Telemetry | ❌ Cloud Sync | ✅ **Strictly Offline** |
| **Active iOS 16/17/18+ Maintenance**| ✅ | ❌ Abandoned | ✅ **Active** |
| **Zero Background Work While Typing** | — | — | ✅ **No timers, no I/O per keypress** |

---

## 📐 Layout Blueprint & Geometry

Key widths are proportional percentages derived directly from AOSP LatinIME `row_qwerty4.xml`:

```
Row 1: │ q │ w │ e │ r │ t │ y │ u │ i │ o │ p │       (each 10%)
Row 2:   │ a │ s │ d │ f │ g │ h │ j │ k │ l │         (5% inset + 10% each)
Row 3: │  ⇧ (15%)  │ z │ x │ c │ v │ b │ n │ m │ ⌫ (15%) │
Row 4: │ ?123 (15%) │ , (10%) │    space (~50%)    │ . (10%) │ return (15%) │
```

---

## 🏗️ Project Architecture

```
The-Keyboard-project/
├── Sources/
│   ├── HostApp/          # Setup checklist, privacy statement & asset catalog
│   ├── Keyboard/         # Custom UIInputViewController keyboard extension
│   └── Shared/           # App Group storage, handshake record, device info
├── Tests/                # Layout math and typing behavior unit tests (52 tests)
├── UITests/              # Touch-layer trials: rollover, hit-testing, hold-repeat (19 tests)
├── Scripts/              # redeploy.sh — renew the 7-day free-team signing
├── docs/                 # Authoritative specifications, ADR logs, constraints & roadmap
├── Makefile              # 1-click bootstrap, build, test & redeploy commands
└── project.yml           # Declarative XcodeGen project specification
```

---

## 🚀 Quick Start

### Setup & Build

```bash
# Clone the repository
git clone https://github.com/Srimi1/The-Keyboard-project.git
cd The-Keyboard-project

# Bootstrap and generate the project
make bootstrap

# Run unit tests & UI trials
make test

# Open in Xcode
open KeyboardProject.xcodeproj
```

---

## 📱 Deploying to an iPhone

1. In Xcode, select the `KeyboardProject` scheme and connect your iPhone.
2. Under **Signing & Capabilities**, select your personal Team for **both** targets (`KeyboardProject` and `KeyboardExtension`).
3. Enable **Developer Mode** on your iPhone (*Settings → Privacy & Security → Developer Mode*).
4. Run the build to install the app on your device.
5. On device: *Settings → General → Keyboard → Keyboards → Add New Keyboard → Keyboard Project → Allow Full Access*.
6. Enable paste permissions: *Settings → Keyboard Project → Paste from Other Apps → Allow*.

The app's setup screen walks these three steps and shows which are done. After that the keyboard lives on the globe key and the app never needs opening again.

> **Free personal team:** signing lapses after 7 days and the keyboard stops working until you re-deploy ([C-23](docs/CONSTRAINTS.md)). The app shows a countdown; `make redeploy` renews it in one command.

---

## 📖 Documentation Index

| Document | Purpose |
| :--- | :--- |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Target models, memory pipelines, App Group data flow. |
| **[docs/CONSTRAINTS.md](docs/CONSTRAINTS.md)** | Verified iOS keyboard platform constraints, limits, and gotchas. |
| **[docs/UI-SPEC.md](docs/UI-SPEC.md)** | Key geometry, row percentages, layers, and long-press mapping. |
| **[docs/CLIPBOARD.md](docs/CLIPBOARD.md)** | Clipboard capture model, retention, and security specifications. |
| **[docs/DECISIONS.md](docs/DECISIONS.md)** | Architectural Decision Records (ADRs) and design choices. |
| **[docs/ROADMAP.md](docs/ROADMAP.md)** | Milestone roadmap from M0 to M6. |
| **[docs/RELEASING.md](docs/RELEASING.md)** | Release checklist, signing guide, and publishing workflow. |

---

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CLAUDE.md](CLAUDE.md) before submitting pull requests.

```bash
make bootstrap
make test
```

---

## 📄 License & Privacy

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.  
Read our [Security & Privacy Statement](SECURITY.md) for details on our 100% offline commitment.
