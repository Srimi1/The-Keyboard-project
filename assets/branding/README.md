# Keyboard Project brand assets

This package turns the ViewMax visual direction into reusable production assets. The final
identity is deliberately monochrome and uses four forms with one uninterrupted central gap.

The meaning is structural rather than decorative:

- The four forms are abstract **keys**, representing typing without drawing a literal keyboard.
- Their combined outer contour becomes a **shield**, representing offline, on-device privacy.
- The white negative space through the center is the **insertion caret**. It is intentionally
  empty: the user controls what enters the keyboard, not the app.
- The split between the forms also expresses a boundary between private input and software.

## Production assets

| Asset | Intended use |
|---|---|
| `exports/app-icon-1024.png` | App Store and Xcode app-icon source; opaque, 1024 × 1024 |
| `source/logo-mark-monochrome.svg` | Black mark for white or very light surfaces |
| `source/logo-mark-reversed.svg` | White mark for black or very dark surfaces |
| `exports/onboarding-hero-1600.jpg` | Host-app onboarding or support material; copy stays native |
| `exports/brand-banner-2048.jpg` | Repository, support site and press-kit header |

The active Xcode app icon is rendered deterministically from the same geometry: a white mark on
an edge-to-edge black field. Previous icon directions are retained under `archive/` for
traceability. The ViewMax result remains a concept source, because generated raster edges are
not suitable for a final logo at small sizes. Run `xcrun swift Scripts/render-brand-assets.swift`
from the repository root to reproduce the app-icon PNGs.

## Usage rules

- Never add an outer rounded-square mask to the app icon; iOS supplies the mask.
- Keep at least one tile-width of clear space around the standalone mark.
- Do not place letters or clipboard content inside the key tiles.
- Use only pure black and pure white. Do not introduce brand colors, gradients, glow, shadows,
  outlines, bevels or photographic texture into the logo.
- The central caret must remain empty negative space; never fill or color it.
- Add headings and buttons as native SwiftUI elements, not baked into the artwork.
- App Store screenshots must show the real signed app/keyboard. The artwork here is not release
  evidence and must not be presented as a product screenshot.

The onboarding and banner illustrations show the keyboard's selectable UI themes and are not
part of the monochrome logo. They must never be used as alternate logo treatments.

## Logo palette

| Token | Value |
|---|---|
| Black | `#000000` |
| White | `#FFFFFF` |

## Approval status

This is brand candidate v2. Visual approval on an actual iPhone Home Screen and an independent
name/mark clearance check remain public-release gates.
