# ADR-001: Framed streaming and plaintext provider SQLite

## Status

Accepted

## Date

2026-08-13

## Context

The Quick Panel must visibly stream `primary`, `secondaryTitle`, and `secondary` without waiting for complete structured records. Provider settings must also load and save provider, model, and API key as one consistent value. The user explicitly accepts plaintext-at-rest API-key risk and requires the provider database to remain separate from history.

## Decision

Provider output uses these uncommon product-owned markers, each on its own line and in strict order:

```text
<<<ENGLISH_COMPANION::PRIMARY>>>
<primary value>
<<<ENGLISH_COMPANION::SECONDARY_TITLE>>>
<secondary title value>
<<<ENGLISH_COMPANION::SECONDARY>>>
<secondary value>
<<<ENGLISH_COMPANION::END>>>
```

Values cannot contain marker text. The incremental parser retains only a possible marker-prefix suffix, emits cumulative typed partials for safe content, and rejects missing, duplicate, unknown, out-of-order, or trailing framing. The UI rejects marker-bearing typed partials as a second boundary.

The app stores exactly one active provider row—`provider`, `model`, and plaintext `api_key`—in `Application Support/EnglishCompanion/provider.sqlite`. This file is separate from `history.sqlite` and uses POSIX mode `0600` where supported. A blank submitted key preserves the existing row's key; it cannot create the first row. The app does not read, migrate, or delete credentials from any previous storage mechanism.

## Alternatives considered

- Complete-record parsing: rejected because each field updated only after an entire record arrived.
- Provider-specific streaming fragments: rejected because provider framing could leak into product/UI state and couple the UI to one SDK.
- Encrypted operating-system credential storage: not selected for this user-authorized change; plaintext local SQLite and its risk disclosure are explicit requirements.
- Combining provider settings with history: rejected to keep credentials out of history lifecycle, exports, and cleanup.

## Consequences

- All three output fields can visibly update on safe model chunks.
- Protocol markers are part of the prompt and parser contract and must change together.
- Provider settings have one throwable load/save boundary, preventing mixed model/key snapshots.
- The API key is recoverable from the SQLite file by any process able to read it; the settings UI must state this plainly.
- Tests use only dummy strings and temporary SQLite files and require no real credential or network access.
