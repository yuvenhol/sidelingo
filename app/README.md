# macOS App

English Companion is a native macOS app with an AppKit shell and SwiftUI interface hosted through `NSHostingView`. It contains no WebView.

## Implemented

- System-wide Translate and Improve hotkey registration
- Explicit Accessibility permission and no-selection outcomes
- Dark Raycast-style SwiftUI Quick Panel
- `Esc` hide and menu-bar lifecycle
- Manual result copy
- DeepSeek processing through SwiftOpenAI with a configurable model
- DeepSeek model settings in UserDefaults and API key storage through KeychainAccess
- SQLite UTF-8 history
- Async Quick Panel loading, success, error and cancellation states

## Test

```bash
swift test
```

The current tests cover input-source decisions, stale clipboard rejection, Accessibility states, panel geometry, hotkey registration, the injected Keychain adapter, SQLite, provider configuration, strict provider output decoding and Quick Panel processing state.

## Build

```bash
./build-app.sh
open -n "dist/English Companion.app"
```

The local build requires the stable `English Companion Local Development` code-signing identity and uses bundle identifier `dev.kris.english-companion`. It deliberately refuses to fall back to ad-hoc signing because that invalidates Accessibility authorization across rebuilds.

## Remaining gate

Chrome selected-text capture through Accessibility is validated end to end. Preview PDF and Obsidian/Electron still need representative validation. The safe pasteboard fallback accepts only changed, stable text and rejects unchanged/conflicting reads. It deliberately does not restore the general pasteboard because macOS provides no atomic conditional write, so restoration could overwrite a concurrent user or clipboard-manager update. A real cross-application fallback E2E check is still required. Provider tests use injected fakes and do not make real network or Keychain calls.
