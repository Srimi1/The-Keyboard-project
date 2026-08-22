# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Privacy & Security Invariant

**The Keyboard Project is 100% offline by design.**

- **Zero Network Traffic:** The keyboard extension contains no networking code, telemetry, analytics, or background sync.
- **Local-Only Storage:** Clipboard history and settings are stored strictly in the local on-device App Group container (`group.com.srijan.keyboardproject`) and never leave your hardware.
- **Sandboxed Execution:** Full Access is requested exclusively for accessing the local pasteboard, triggering system haptics, and playing typing sounds.

## Reporting a Vulnerability

If you discover a potential security or privacy issue, please do not open a public issue. Instead, report it directly to the repository maintainer via private message or email at:

**srijan@example.com** (or open a private security advisory on GitHub).

We take security and input privacy extremely seriously and will investigate and respond promptly.
