# Contributing to The Keyboard Project

Thank you for your interest in contributing to **The Keyboard Project**!

Our goal is to build the definitive personal iOS keyboard extension that brings the authentic Android Gboard layout, interaction feel, and multi-item clipboard history to iPhone, while maintaining strict privacy and native performance.

---

## Development Workflow

### Prerequisites

- macOS with Xcode 26 or newer (the deployment target remains iOS 16)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Git

### Project Setup

The `.xcodeproj` file is generated from `project.yml` and is not tracked in git.

```bash
# 1. Clone the repository
git clone https://github.com/Srimi1/The-Keyboard-project.git
cd The-Keyboard-project

# 2. Bootstrap XcodeGen & generate project
make bootstrap

# 3. Open in Xcode
open KeyboardProject.xcodeproj
```

### Running Tests

You can run the unit test suite and touch-layer UI trials locally:

```bash
make test
```

---

## Core Architectural Invariants

Every contribution must honor the core rules documented in [CLAUDE.md](CLAUDE.md) and [docs/CONSTRAINTS.md](docs/CONSTRAINTS.md):

1. **Zero Network, Ever**: The extension never makes network calls. No sync, no analytics, no crash reporters ([ADR-005](docs/DECISIONS.md)).
2. **Memory Budget**: Extension physical memory footprint must remain **≤ 40 MB** steady state (against iOS jetsam limit near ~60 MB).
3. **Typing Always Works**: Even if Full Access is revoked or App Groups fail, the keyboard must never crash and must always continue to type plain text.
4. **Android Gboard Reference**: Match the owner's Android Gboard layout and feel where iOS extension rules permit it; platform safety and privacy take precedence ([docs/UI-SPEC.md](docs/UI-SPEC.md)).

---

## Submitting Pull Requests

1. Fork the repo and create your feature branch: `git checkout -b feature/amazing-feature`
2. Commit your changes: `git commit -m 'Add amazing feature'`
3. Verify the project builds clean without warnings: `xcodegen generate && xcodebuild ...`
4. Push to your branch: `git push origin feature/amazing-feature`
5. Open a Pull Request with the completed checklist.
