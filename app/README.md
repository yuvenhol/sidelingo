# SideLingo macOS App

SideLingo is a native macOS app with an AppKit shell and SwiftUI interface hosted through `NSHostingView`. It contains no WebView.

## Implemented

- System-wide Translate and Improve hotkey registration
- Explicit Accessibility permission and no-selection outcomes
- Dark Raycast-style SwiftUI Quick Panel
- `Esc` hide and menu-bar lifecycle
- Manual result copy
- DeepSeek processing through SwiftOpenAI with the official `deepseek-v4-flash` default alias and a configurable model
- DeepSeek provider, model and intentionally unencrypted API key storage in a dedicated `provider.sqlite`
- Product-owned framed text parsing with cumulative streaming for every output field
- SQLite UTF-8 history
- Pre-SQLite migration into `Application Support/SideLingo`: atomic whole-directory move when possible, otherwise a staged SQLite online backup that never overwrites a current database
- Async Quick Panel loading, success, error and cancellation states

## Test

```bash
swift test
```

The current tests cover input-source decisions, stale clipboard rejection, Accessibility states, panel geometry, hotkey registration, SQLite provider/history storage, strict framed output parsing, provider configuration and Quick Panel processing state.

## Build

```bash
./build-app.sh
open -n "dist/SideLingo.app"
```

The local build uses `SIDELINGO_SIGNING_IDENTITY`, defaulting to the stable `SideLingo Local Development` code-signing identity, and bundle identifier `dev.kris.sidelingo`. It deliberately refuses to fall back to ad-hoc signing because that invalidates Accessibility authorization across rebuilds. `./build-app.sh --install` installs to `~/Applications/SideLingo.app`.

## Remaining gate

Chrome selected-text capture through Accessibility was validated on the predecessor app identity. Because SideLingo uses the new bundle identifier `dev.kris.sidelingo`, macOS does not transfer the old Accessibility grant; the first SideLingo installation requires one authorization and a fresh representative E2E check. Preview PDF and Obsidian/Electron still need representative validation. The safe pasteboard fallback accepts only changed, stable text and rejects unchanged/conflicting reads. It deliberately does not restore the general pasteboard because macOS provides no atomic conditional write, so restoration could overwrite a concurrent user or clipboard-manager update. A real cross-application fallback E2E check is still required. Provider tests use injected fakes, dummy strings and temporary SQLite files; they do not make real network calls or access real credentials.
