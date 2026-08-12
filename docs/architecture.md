# Architecture

## Current decision

English Companion is a native macOS app with no WebView.

```text
AppKit shell
├── NSPanel / Workspace windows
├── global hotkeys
├── Accessibility selected text
├── pasteboard fallback
├── Keychain
└── app lifecycle

SwiftUI presentation via NSHostingView
├── Quick Panel
├── Workspace
├── History / Glossary / Review
└── shared dark design tokens

Swift core
├── translate / improve workflows
├── provider abstraction
├── SQLite history and learning data
├── ECDICT lookup
└── export
```

## Source layout

- `app/` — current Swift package and macOS app.
- `prototype/` — approved interaction and visual reference; not production code.
- `docs/PRD-v0.1.md` — product requirements and acceptance criteria.
- `docs/model-evaluation.md` — provider quality evaluation plan.

## Validated

- AppKit floating panel and menu-bar lifecycle.
- SwiftUI Quick Panel hosted in AppKit.
- Deep dark Raycast visual direction.
- System-wide hotkey registration.
- Explicit Accessibility permission/no-selection outcomes.
- Chrome real selected-text capture through Accessibility.
- Stable local code-signing requirement across rebuilds.
- DeepSeek-only provider slice with fixed `https://api.deepseek.com`, official `deepseek-v4-flash` default alias, and configurable model.
- SwiftOpenAI request/response handling with JSON mode and strict product-owned output decoding.
- KeychainAccess credential adapter covered through an injected test backend.
- UserDefaults stores only provider and model settings.
- SQLite UTF-8 history round trip.
- Pasteboard change detection and conflict rejection in unit tests; fallback never restores the general pasteboard because macOS exposes no atomic conditional write.
- `Esc` hides the panel without quitting the app.

## Remaining architecture gate

Real selected-text capture still needs representative validation from:

1. Preview PDF;
2. Obsidian/Electron.

The implemented pasteboard fallback still needs real cross-application E2E verification that it:

- never accepts unchanged clipboard content;
- accepts only text whose change count remains stable across the read;
- returns explicit unchanged/conflict/unsupported outcomes;
- leaves the copied selection on the general pasteboard instead of risking a TOCTOU overwrite while restoring stale content.

## Product constraints

- No WebView or browser runtime.
- No automatic clipboard overwrite.
- API keys live in macOS Keychain.
- History, learning data and ECDICT stay local.
- The current provider slice exposes only DeepSeek; later providers can share the same provider contract after evaluation.
