# Theme preview evidence

These images are deterministic captures of the real SwiftUI keyboard renderer in the Debug
host preview, using the
`-keyboardPreview -keyboardTheme <theme> -keyboardGlobe -cleanPreview` launch flags. The
explicit globe flag mirrors the measured physical-iPhone bottom row; it does not turn the host
preview into a real keyboard extension.

| File | Theme | Capture surface |
| --- | --- | --- |
| `light-iphone17.png` | Light | iPhone 17 simulator, 1206 × 2622 |
| `black-iphone17.png` | Black | iPhone 17 simulator, 1206 × 2622 |
| `neon-iphone17.png` | Neon | iPhone 17 simulator, 1206 × 2622 |

These captures prove the app renderer and layout, not physical-extension performance or device
acceptance. Signed iPhone evidence belongs in `docs/release-evidence/` and must be tied to an
exact commit as described in `docs/DEVICE-ACCEPTANCE.md`.
