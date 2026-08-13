# Architecture

## Current decision

SideLingo is a native macOS app with no WebView.

```text
AppKit shell
├── NSPanel / Workspace windows
├── global hotkeys
├── Accessibility selected text
├── pasteboard fallback
├── Application Support storage
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
├── separate SQLite provider settings with an unencrypted API key
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
- SwiftOpenAI 4.5.1 `startStreamedChat(parameters:)` handling through `CancellationSafeHTTPClient` and redirect rejection.
- A strict product-owned framed text response with ordered `PRIMARY`, `SECONDARY_TITLE`, `SECONDARY`, and `END` markers; all three typed fields publish cumulative safe partials.
- A single complete provider/model/API-key row in `Application Support/SideLingo/provider.sqlite`, separate from `history.sqlite`; the API key is intentionally plaintext and the database uses `0600` where supported.
- A startup migration runs before either SQLite store opens. `Application Support/EnglishCompanion` is recognized only as the legacy compatibility source: the whole directory moves atomically when the canonical directory is absent; when both directories exist, each missing current database is copied through SQLite's online-backup API into a hidden staging file and atomically renamed only after a complete close and `0600` permission update. SQLite resolves WAL and rollback-journal state itself; failed or interrupted staging artifacts are removed before retry, current databases are never overwritten, and the legacy database remains as rollback evidence.
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
- The settings UI must disclose that the API key is stored unencrypted in local SQLite.
- Provider settings load and save as one complete value; a blank key preserves an existing key but cannot create the first row.
- History, learning data and ECDICT stay local.
- The current provider slice exposes only DeepSeek; later providers can share the same provider contract after evaluation.

See [ADR-001](decisions/001-framed-streaming-and-plaintext-provider-sqlite.md) for the wire and storage decisions.
