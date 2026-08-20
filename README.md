# SideLingo

[![CI](https://github.com/yuvenhol/sidelingo/actions/workflows/ci.yml/badge.svg)](https://github.com/yuvenhol/sidelingo/actions/workflows/ci.yml)

SideLingo is a lightweight, keyboard-first native macOS companion for Chinese–English workplace communication. It translates, improves writing, and turns real communication into local learning history without embedding a browser runtime.

> Early-stage project: the native Quick Panel, DeepSeek streaming path, and bundled offline ECDICT lookup are implemented; Workspace and broader learning workflows remain on the roadmap.

## Current status

- Native **AppKit shell + SwiftUI UI**, with no WebView.
- The Quick Panel, menu-bar lifecycle, Translate/Improve hotkeys, DeepSeek streaming, bundled ECDICT lookup, and local SQLite persistence are implemented.
- Translate checks the local dictionary first for exact words/phrases, normalized punctuation variants, and inflected forms; misses fall back to DeepSeek. Improve always uses the provider.
- The new bundle identifier is `dev.kris.sidelingo`; macOS requires one fresh Accessibility grant after installation.
- Accessibility-selected text was validated in Chrome on the predecessor app identity. Preview PDF, Obsidian/Electron, and the real pasteboard fallback still need representative E2E validation.
- The pasteboard fallback accepts only changed, stable text and deliberately does not restore stale clipboard contents because macOS offers no atomic conditional write.
- Provider tests use fakes and make no real network requests.

## Repository layout

- [`app/`](app/) — Swift package and native macOS application.
- [`prototype/`](prototype/) — approved interaction and visual reference; not production code.
- [`docs/PRD-v0.1.md`](docs/PRD-v0.1.md) — product requirements and acceptance criteria (Chinese).
- [`docs/architecture.md`](docs/architecture.md) — current architecture and remaining gates.
- [`docs/model-evaluation.md`](docs/model-evaluation.md) — task-specific provider evaluation plan.

## Implemented now

- Two explicit workflows: **Translate** and **Improve**.
- Native AppKit shell with a SwiftUI Quick Panel; no WebView or browser runtime.
- System-wide hotkeys with Accessibility-selected text first and a conflict-safe pasteboard fallback.
- DeepSeek-only BYOK processing through SwiftOpenAI, using `deepseek-v4-flash` by default.
- Cumulative streaming for the primary result, secondary title, and explanation/back-translation.
- Local SQLite history plus a separate `provider.sqlite` configuration database.
- Bundled read-only full ECDICT SQLite with 3,402,564 entries, exact/phrase lookup, lemma resolution, complete non-empty field presentation, local history classification, and macOS system pronunciation.
- Reproducible ECDICT preparation from a pinned upstream archive with SHA-256 checks, a tracked artifact manifest, `quick_check`, and bundled MIT attribution.
- Startup migration from the predecessor Application Support directory without overwriting a current database.

> **Security note:** the API key is intentionally stored as unencrypted plaintext in local `provider.sqlite` with owner-only `0600` permissions. It is not written to source, logs, history, tests, or exports.

## Roadmap

- Workspace, searchable history UI, glossary, and review flows.
- Additional providers only after task-specific evaluation; the current build exposes DeepSeek only.
- Anki and Markdown export.

## Development

The normal contributor workflow does not require a signing certificate:

```bash
cd app
swift test
swift build
python3 -m unittest scripts/tests/test_build_ecdict.py
```

Run the interaction-prototype tests separately:

```bash
cd prototype
node --test tests/app-model.test.mjs
```

## Signed local app

`app/build-app.sh` creates the native `.app` bundle and deliberately requires a stable code-signing identity so macOS Accessibility authorization survives rebuilds:

```bash
cd app
./scripts/prepare-ecdict.sh
SIDELINGO_SIGNING_IDENTITY="Your Code Signing Identity" ./build-app.sh
open -n "dist/SideLingo.app"
```

The preparation script downloads the pinned full `stardict.7z` archive and `lemma.en.txt`, verifies archive, extracted CSV, and lemma SHA-256 hashes, then builds the ignored `Resources/ECDICT/ecdict.sqlite` artifact. The generated database is approximately 466 MB and is copied into the signed app but is not committed to this repository.

The maintainer's default identity is `SideLingo Local Development`; it is local-only and is not included in this repository. Distribution still requires Developer ID signing, notarization, and stapling.

## Next

1. Re-authorize the new `dev.kris.sidelingo` bundle once and refresh the cross-application selection E2E.
2. Validate Preview PDF, Obsidian/Electron, and the real pasteboard fallback.
3. Validate framed streaming with anonymous representative inputs.
4. Implement Workspace and learning workflows incrementally.

Architecture decisions are documented in [`ADR-001`](docs/decisions/001-framed-streaming-and-plaintext-provider-sqlite.md).

## License

No open-source license has been granted for SideLingo's own source yet. The repository is publicly visible, but reuse and redistribution rights remain reserved until a license is added. The separately attributed ECDICT data resource is provided under its upstream MIT license; see [`app/Resources/ECDICT/ATTRIBUTION.md`](app/Resources/ECDICT/ATTRIBUTION.md).
