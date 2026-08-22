<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="The Keyboard Project Logo" style="border-radius: 28px; box-shadow: 0 8px 24px rgba(0,0,0,0.3);">
</p>

<h1 align="center">The Keyboard Project</h1>

<p align="center">
  <strong>An iPhone keyboard engineered to bring the authentic Android Gboard layout, tactile feel, and multi-item clipboard history to iOS.</strong>
</p>

<p align="center">
  <a href="https://github.com/Srimi1/The-Keyboard-project/actions/workflows/ci.yml"><img src="https://github.com/Srimi1/The-Keyboard-project/actions/workflows/ci.yml/badge.svg" alt="CI Status"></a>
  <img src="https://img.shields.io/badge/iOS-16.0%2B-000000?logo=apple&logoColor=white" alt="iOS 16.0+">
  <img src="https://img.shields.io/badge/Swift-5.0%20%7C%206.0-FA7343?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Memory-%E2%89%A440MB%20Budget-2ea44f" alt="Memory Budget">
  <img src="https://img.shields.io/badge/Privacy-100%25%20Offline-success" alt="Offline Privacy">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
</p>

---

## 🎯 The Problem

Switching from Android to iPhone costs you two essential daily workflows:

1. **The Layout & Muscle Memory:** Gboard's dedicated punctuation row, key proportions, symbol positions, and long-press maps.
2. **The Clipboard History:** Android's Gboard maintains a persistent history of copied snippets, links, and text. iOS keeps exactly **one** item at a time, overwriting your history instantly.

Google abandoned development of Gboard for iOS at **v2.3.19 (May 2022)**, and Apple's native keyboard has no clipboard manager.

**The Keyboard Project** fixes this with a clean, privacy-first, zero-network custom keyboard extension built natively in Swift for iOS.

---

## ✨ Features

- ⌨️ **Accurate Gboard Geometry:** Key-width percentages sourced directly from AOSP LatinIME specifications (10% letter width, centered second row, Gboard function row).
- 📋 **Persistent Multi-Item Clipboard:** Captures and stores your copy history securely in an isolated App Group container on your device.
- 🔒 **100% Offline & Private:** **Zero network capability.** No analytics, no telemetry, no remote servers, and no crash reporters. What you type stays on your physical phone ([ADR-005](docs/DECISIONS.md)).
- ⚡ **Lightweight & Jetsam-Safe:** Strictly engineered within a **≤ 40 MB memory budget** to prevent silent iOS background termination ([CONSTRAINTS.md](docs/CONSTRAINTS.md)). The shipping extension runs **no timers and no per-appearance disk I/O** — the development harness compiles out of Release entirely.
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

## 🏗️ Project Architecture

```
The-Keyboard-project/
├── Sources/
│   ├── HostApp/          # Setup checklist, privacy statement & asset catalog
│   ├── Keyboard/         # Custom UIInputViewController keyboard extension
│   └── Shared/           # App Group storage, handshake record, device info
├── Tests/                # Layout math and typing behavior unit tests (52)
├── UITests/              # Touch-layer trials: rollover, hit-testing, hold-repeat (19)
├── Scripts/              # redeploy.sh — renew the 7-day free-team signing
├── docs/                 # Authoritative specifications, ADR logs, constraints & roadmap
└── project.yml           # Declarative XcodeGen project specification
```

---

## 🚀 Quick Start

### 1. Requirements

- macOS running Xcode 15 or higher.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- An Apple ID (Free Personal Team or Developer Account).

### 2. Build and Run

```bash
# Clone the repository
git clone https://github.com/Srimi1/The-Keyboard-project.git
cd The-Keyboard-project

# Generate the .xcodeproj file
xcodegen generate

# Open in Xcode
open KeyboardProject.xcodeproj
```

To run build verification directly from terminal:

```bash
# Build
xcodebuild -project KeyboardProject.xcodeproj -scheme KeyboardProject \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Test — 52 unit tests + 19 touch-layer UI trials
xcodebuild test -project KeyboardProject.xcodeproj -scheme KeyboardProject \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

---

## 📱 Deploying to an iPhone

1. In Xcode, select the `KeyboardProject` scheme and connect your iPhone.
2. Under **Signing & Capabilities**, select your personal Team for **both** targets (`KeyboardProject` and `KeyboardExtension`).
3. Enable **Developer Mode** on your iPhone (*Settings → Privacy & Security → Developer Mode*).
4. Run the build to install the app on your device.
5. On device: *Settings → General → Keyboard → Keyboards → Add New Keyboard → Keyboard Project → Allow Full Access*.
6. Enable paste permissions: *Settings → Keyboard Project → Paste from Other Apps → Allow*.

The app's setup screen walks these three steps and shows which are done. After that the
keyboard lives on the globe key and the app never needs opening again.

> **Free personal team:** signing lapses after 7 days and the keyboard stops working until you
> re-deploy ([C-23](docs/CONSTRAINTS.md)). The app shows a countdown; `./Scripts/redeploy.sh`
> renews it in one command.

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

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
