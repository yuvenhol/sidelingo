#!/usr/bin/env python3
"""Validate a generated ECDICT artifact before packaging."""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

ENTRY_COLUMNS = (
    "word",
    "phonetic",
    "definition",
    "translation",
    "pos",
    "collins",
    "oxford",
    "tag",
    "bnc",
    "frq",
    "exchange",
    "detail",
    "audio",
    "normalized",
)
LEMMA_COLUMNS = ("form", "lemma")


class ECDICTValidationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_database(database_path: Path, manifest_path: Path) -> dict[str, int]:
    database_path = Path(database_path)
    manifest_path = Path(manifest_path)
    if not database_path.is_file():
        raise ECDICTValidationError(f"ECDICT database is missing: {database_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ECDICTValidationError(f"Invalid ECDICT manifest: {error}") from error

    _validate_manifest_shape(manifest)
    actual_digest = sha256(database_path)
    if actual_digest != manifest["database_sha256"]:
        raise ECDICTValidationError(
            f"ECDICT database SHA-256 mismatch: expected {manifest['database_sha256']}, got {actual_digest}"
        )

    connection = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
    try:
        check = connection.execute("PRAGMA quick_check").fetchone()
        if check is None or check[0] != "ok":
            raise ECDICTValidationError(f"ECDICT quick_check failed: {check!r}")
        _validate_columns(connection, "entries", ENTRY_COLUMNS)
        _validate_columns(connection, "lemmas", LEMMA_COLUMNS)
        entries = connection.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        lemmas = connection.execute("SELECT COUNT(*) FROM lemmas").fetchone()[0]
        if entries != manifest["entries"] or lemmas != manifest["lemmas"]:
            raise ECDICTValidationError(
                f"ECDICT count mismatch: entries={entries}, lemmas={lemmas}"
            )
        for word, expected_translation in manifest["representative_entries"].items():
            row = connection.execute(
                "SELECT translation FROM entries WHERE word = ? COLLATE NOCASE",
                (word,),
            ).fetchone()
            if row is None or row[0] != expected_translation:
                raise ECDICTValidationError(f"ECDICT representative entry mismatch: {word}")
        for form, expected_lemma in manifest["representative_lemmas"].items():
            row = connection.execute(
                "SELECT lemma FROM lemmas WHERE form = ? COLLATE NOCASE",
                (form,),
            ).fetchone()
            if row is None or row[0] != expected_lemma:
                raise ECDICTValidationError(f"ECDICT representative lemma mismatch: {form}")
    except sqlite3.Error as error:
        raise ECDICTValidationError(f"ECDICT SQLite validation failed: {error}") from error
    finally:
        connection.close()
    return {"entries": entries, "lemmas": lemmas}


def _validate_manifest_shape(manifest: object) -> None:
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ECDICTValidationError("Unsupported ECDICT manifest schema")
    for key in ("database_sha256", "entries", "lemmas", "representative_entries", "representative_lemmas"):
        if key not in manifest:
            raise ECDICTValidationError(f"ECDICT manifest is missing {key}")
    source = manifest.get("source")
    if not isinstance(source, dict):
        raise ECDICTValidationError("ECDICT manifest source metadata is missing")
    for key in ("commit", "archive_sha256", "csv_sha256", "lemma_sha256"):
        if not source.get(key):
            raise ECDICTValidationError(f"ECDICT manifest source is missing {key}")
    for key in ("database_sha256",):
        value = manifest[key]
        if not isinstance(value, str) or len(value) != 64:
            raise ECDICTValidationError(f"ECDICT manifest has invalid {key}")


def _validate_columns(connection: sqlite3.Connection, table: str, expected: tuple[str, ...]) -> None:
    queries = {
        "entries": "PRAGMA table_info(entries)",
        "lemmas": "PRAGMA table_info(lemmas)",
    }
    try:
        query = queries[table]
    except KeyError as error:
        raise ECDICTValidationError(f"Unsupported ECDICT table: {table}") from error
    actual = tuple(row[1] for row in connection.execute(query))
    if actual != expected:
        raise ECDICTValidationError(
            f"ECDICT schema mismatch for {table}: expected {expected!r}, got {actual!r}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    arguments = parser.parse_args()
    summary = validate_database(arguments.database, arguments.manifest)
    print(f"ECDICT validated: entries={summary['entries']} lemmas={summary['lemmas']}")


if __name__ == "__main__":
    main()
