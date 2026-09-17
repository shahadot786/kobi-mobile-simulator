# Contributing to Kobi Mobile Simulator

Thanks for considering a contribution — this doc covers how to get set up
and what a good pull request looks like.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- No third-party package manager (SwiftPM only, and only if a dependency is
  ever introduced)

## Getting started

```bash
git clone https://github.com/shahadot786/kobi-mobile-simulator.git
cd kobi-mobile-simulator
open Kobi.xcodeproj
```

Select the **Kobi** scheme and **My Mac** as the run destination, then
Cmd+R. No signing setup is required to build and run locally — Xcode's
"Automatic" signing handles that with your own Apple ID.

## Before opening a pull request

- Run `swiftformat .` — formatting is enforced via `.swiftformat`
  (4-space indent, no semicolons, `self` removed, 120-col width).
- Check `swiftlint` output — see `.swiftlint.yml` for the active rules.
- Build and run the app; verify your change works in both Light and Dark
  appearance (Help menu → Toggle Appearance, or ⌘⇧D).
- If you're adding user-facing text, add it through
  `Localizable.xcstrings` (Xcode's String Catalog editor, or
  `Text("your.key")` / `String(localized: "your.key")` in code) — not as a
  hardcoded string literal.
- If you're touching the device catalog, edit
  `Kobi/Resources/DeviceCatalog.json` — it's data-driven on purpose, not
  hardcoded in Swift.

## Pull request guidelines

- Keep PRs focused — one feature or fix per PR is easier to review than a
  bundle of unrelated changes.
- Describe what changed and why in the PR description; screenshots or a
  short screen recording are appreciated for UI changes.
- Reference any related issue with `Fixes #123` / `Relates to #123`.
- Make sure the project builds cleanly before requesting review.

## Reporting bugs / requesting features

Please use the issue templates under **Issues → New Issue** — they ask for
the information needed to reproduce a bug or evaluate a feature request.

## Code of conduct

This project follows the guidelines in `CODE_OF_CONDUCT.md`. Be respectful
and constructive in issues, PRs, and discussions.
