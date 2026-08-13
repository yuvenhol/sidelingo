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
<<<SIDELINGO::PRIMARY>>>
<primary value>
<<<SIDELINGO::SECONDARY_TITLE>>>
<secondary title value>
<<<SIDELINGO::SECONDARY>>>
<secondary value>
<<<SIDELINGO::END>>>
```

Values cannot contain marker text. The incremental parser retains only a possible marker-prefix suffix, emits cumulative typed partials for safe content, and rejects missing, duplicate, unknown, out-of-order, or trailing framing. The UI rejects marker-bearing typed partials as a second boundary.

The app stores exactly one active provider row—`provider`, `model`, and plaintext `api_key`—in `Application Support/SideLingo/provider.sqlite`. This file is separate from `history.sqlite` and uses POSIX mode `0600` where supported. A blank submitted key preserves the existing row's key; it cannot create the first row.

Before opening either SQLite store, startup recognizes `Application Support/EnglishCompanion` only as a legacy migration source. If `SideLingo` does not exist, the legacy directory moves atomically. If both directories exist, each missing `history.sqlite` or `provider.sqlite` is copied through SQLite's online-backup API into a hidden staging database. SQLite resolves committed WAL content and hot rollback journals while producing the consistent snapshot; SideLingo sets the staging database to `0600` and atomically renames it to the final path only after backup and close succeed. Failed or interrupted staging families—including `-wal`, `-shm`, and `-journal`—are removed before a retry. Existing current databases are never overwritten, unknown legacy files remain in place, and the legacy database remains available as rollback evidence. Any backup or cleanup failure prevents provider startup without logging stored values.

## Alternatives considered

- Complete-record parsing: rejected because each field updated only after an entire record arrived.
- Provider-specific streaming fragments: rejected because provider framing could leak into product/UI state and couple the UI to one SDK.
- Encrypted operating-system credential storage: not selected for this user-authorized change; plaintext local SQLite and its risk disclosure are explicit requirements.
- Combining provider settings with history: rejected to keep credentials out of history lifecycle, exports, and cleanup.

## Consequences

- All three output fields can visibly update on safe model chunks.
- Protocol markers are part of the prompt and parser contract and must change together.
- Provider settings have one throwable load/save boundary, preventing mixed model/key snapshots.
- Application Support migration is idempotent and must complete before either database is opened.
- The API key is recoverable from the SQLite file by any process able to read it; the settings UI must state this plainly.
- Tests use only dummy strings and temporary SQLite files and require no real credential or network access.
