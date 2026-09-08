# AI working-session contract

This file mirrors the active repository rules in `AGENTS.md` for tools that discover
`CLAUDE.md` first.

## Ground truth

- `README.md`: current status and commands.
- `docs/PRODUCT.md`: v1 scope.
- `docs/ARCHITECTURE.md`: implementation boundaries.
- `docs/CLIPBOARD.md`: clipboard privacy and storage contract.
- `docs/ROADMAP.md`: remaining gates.
- `docs/BUG-REGISTER.md`: defects and evidence gaps.
- `docs/DECISIONS.md`: decision history; add a superseding ADR rather than rewriting history.

## Non-negotiable behavior

The codebase is dependency-free native Swift, UIKit and SwiftUI. Do not introduce
KeyboardKit, Node.js or a backend. The product is iPhone-only and English (US) for v1.

Plain typing, deletion and the real UIKit next-keyboard control must work with Full Access
off. Never read clipboard values on app/extension launch, foregrounding or keyboard
appearance. Clipboard saving begins only through a user-tapped `PasteButton` after the local
retention notice. Do not add extension-to-host-app launching. No app-owned networking,
telemetry, advertising, accounts or clipboard logging is permitted.

Suggestions, autocorrect, glide typing and automatic clipboard capture are deferred until
after v1 and require new ADRs plus device/privacy/memory evidence.

## Working discipline

Preserve the dirty tree. Use one writer in a checkout and run Xcode work serially against one
named destination. Add focused regressions before integration tests. Record failures plainly;
simulator preview coverage is not physical-extension evidence. Never publish or perform a
release action without explicit authorization.
