# Keyboard theme assets

An asset is a reusable visual ingredient: colors, gradients, icon choices, key surfaces,
pressed states, borders, shadows and reference previews. It is not a separate bitmap for every
letter. The shipping keys are native SwiftUI vectors so they remain sharp, accessible and cheap
inside the keyboard extension.

## Theme set

- **Light** — cool off-white canvas, white/silver keys and a restrained blue accent.
- **Black** — true near-black canvas, charcoal keys, white labels and a cyan accent.
- **Neon** — midnight navy, violet function keys, cyan edges and a deliberately shallow glow.
- **System** — follows iOS and resolves to Light or Black.

`Sources/Keyboard/KeyboardTheme.swift` is the runtime source of truth. `theme-tokens.json`
mirrors those values as a design handoff. `icon-map.json` records the semantic SF Symbols used
for toolbar and function-key icons.

## Folder map

```text
assets/themes/
  README.md                 this contract
  theme-tokens.json         editable palette and surface tokens
  icon-map.json             semantic vector-icon mapping
  concepts/                 ViewMax visual-direction work
  previews/                 screenshots from the real SwiftUI keyboard preview
```

The checked-in previews are `light-iphone17.png`, `black-iphone17.png` and
`neon-iphone17.png`. They were captured from the real keyboard renderer at 1206 × 2622 on the
iPhone 17 simulator. See `previews/README.md` for the evidence boundary.

The ViewMax concept board is inspiration, not an implementation screenshot. Generated UI can
misdraw text or geometry; the simulator previews are the evidence for what the app actually
renders. The extension itself stays transparent for iOS keyboard glass behavior, while the
preview canvas visualizes each theme's intended surrounding tone.

## Adding a theme later

1. Add a stable `KeyboardAppearance` raw value without renaming existing values.
2. Add one complete `KeyboardTheme` token set; do not special-case individual letters.
3. Add the same palette to `theme-tokens.json`.
4. Capture a clean simulator preview and test contrast, pressed state and all panels.
5. Measure extension memory on a signed device before release.
