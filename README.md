# Kobi Mobile Simulator

Native macOS app for developers to test responsive websites inside
pixel-accurate mobile/tablet device frames (viewport, DPR, notch shape,
User-Agent) without a physical device or browser dev tools.

- Product concept, feature inventory, and screen-by-screen design spec:
  see `docs/DESIGN_BRIEF.md` (local only — not tracked in git)
- Phased build plan, tech decisions, and known risks: see
  `docs/ROADMAP.md` (local only — not tracked in git)

## Stack

- Swift / SwiftUI (native macOS app, no Electron/web wrapper)
- `WKWebView` per simulated device
- Localization via Apple's native String Catalog (`Localizable.xcstrings`)

## Status

Pre-scaffolding. No Xcode project yet — see ROADMAP.md Phase 0.
