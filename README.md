# Kobi Mobile Simulator

Native macOS app for developers, designers, and QA to test responsive
websites inside pixel-accurate mobile/tablet device frames (viewport, device
pixel ratio, notch/bezel shape, User-Agent) — without a physical device or a
browser dev-tools panel.

Works against localhost, staging, or production URLs and is framework
agnostic: since each device frame renders the page in a real `WKWebView`,
any stack (React, Vue, Angular, WordPress, static HTML) just works.

## Why

Browser dev-tools responsive mode approximates a device's viewport but
doesn't render through a real mobile rendering engine, doesn't show multiple
devices side by side, and isn't a first-class way to present work to a
client or teammate. Kobi renders each simulated device through an actual
WebKit engine and lets you line several devices up on one canvas for
side-by-side comparison, capture, and review.

## Features

- **Device catalog** — searchable, data-driven catalog of phones, tablets,
  and desktop viewports (viewport size, DPR, notch/bezel shape, User-Agent),
  designed to grow after ship without an app rebuild.
- **Single device simulator** — load any URL into an accurate device frame
  with live reload as the page changes.
- **Multi-device canvas** — arrange multiple devices side by side on one
  canvas to compare layouts simultaneously.
- **Capture & export** — screenshot and screen-recording export of a
  simulated device or the whole canvas.
- **Light / Dark / System appearance** — follows macOS semantic colors and
  materials in both themes.
- **Custom devices** — add and manage your own device definitions alongside
  the built-in catalog.

## Stack

- Swift / SwiftUI (native macOS app — no Electron/Tauri/web wrapper)
- `WKWebView` (via `NSViewRepresentable`) renders each simulated device's
  viewport with a real WebKit engine
- Localization via Apple's native String Catalog (`Localizable.xcstrings`)
- Device catalog is a data-driven external JSON/bundle resource, not
  hardcoded in Swift/UI code

## Requirements

- macOS 14 (Sonoma) or later — to run the built app
- Xcode 15 or later — to build from source
- No third-party dependencies to install; SwiftPM only, and only if one is
  ever introduced

## Building & running

```bash
git clone https://github.com/shahadot786/kobi-mobile-simulator.git
cd kobi-mobile-simulator
open Kobi.xcodeproj
```

Select the **Kobi** scheme with **My Mac** as the run destination, then
Cmd+R. Xcode's automatic signing handles code signing locally with your own
Apple ID — no paid developer account or extra setup needed to build and run.

## Project docs

Internal planning docs (design brief, phased roadmap) are intentionally kept
local and untracked (see `.gitignore`) rather than published — the source
code here is the public, canonical reference. `CLAUDE.md` documents the
locked-in technical decisions and conventions already configured in this
repo (formatting, linting, editor config).

## Contributing

Contributions are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) for
setup instructions and pull request guidelines. Please also read the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE)

## Status

Active development. Core simulator, device catalog, multi-device canvas,
capture/export, simulation depth (touch, network throttling, kiosk/PWA,
keyboard overlay), workspaces, and accessibility/localization polish are
implemented. Distribution (code signing, notarization) is intentionally
out of scope for now — see [Building & running](#building--running) above
for how to build from source in the meantime.
