# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

No Xcode project or source code exists yet — this repo currently contains
only planning docs and tooling config (`.gitignore`, `.gitattributes`,
`.editorconfig`, `.swiftformat`, `.swiftlint.yml`). Do not assume a build
exists; check before running build/test/lint commands.

Before any product, architecture, or roadmap question, read
`docs/DESIGN_BRIEF.md` (feature spec, screen inventory, light/dark spec) and
`docs/ROADMAP.md` (phased build plan, locked-in tech decisions, known risks)
— these are gitignored (local planning docs, not committed) but are the
source of truth for scope and sequencing. Don't re-derive decisions already
made there.

## Locked-in technical decisions (do not re-litigate without asking)

- **Native Swift/SwiftUI macOS app** — no Electron/Tauri/web wrapper.
- **`WKWebView`** (via `NSViewRepresentable`) renders each simulated device's
  viewport — real WebKit engine, not a Chromium embed.
- **Localization**: Apple's native String Catalog (`Localizable.xcstrings`)
  with `String(localized:)` / SwiftUI `Text("key")`. Not a custom JSON/`.strings`
  loader — use Xcode's built-in extraction and pluralization tooling.
- **Light/Dark/System appearance**: implement via macOS semantic colors
  (`labelColor`, `windowBackgroundColor`, `controlAccentColor`, etc.), never
  hardcoded hex values, so the app follows system materials/vibrancy
  correctly in both themes.
- **Device catalog** must be data-driven (external JSON/bundle resource), not
  hardcoded in Swift/UI code — the catalog is expected to grow after ship
  without an app rebuild.
- Distribution channel (Mac App Store vs. direct/notarized) is an **open
  decision** flagged in `docs/ROADMAP.md` — it affects sandboxing for
  localhost access and screen recording. Ask before assuming one.

## Conventions already configured

- Swift formatting: `.swiftformat` (4-space indent, no semicolons, `self`
  removed, 120-col width) — run `swiftformat .` before considering Swift
  code done, once the project exists.
- Swift linting: `.swiftlint.yml` (120-col warning / 160 error line length,
  `force_unwrapping` opt-in as a warning).
- `.editorconfig` governs indentation for non-Swift files (2-space for
  JSON/YAML, LF line endings, final newline).
