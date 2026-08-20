#!/usr/bin/env python3
"""Build SideLingo's read-only ECDICT SQLite resource."""

from __future__ import annotations

import argparse
import csv
import os
import re
import sqlite3
import tempfile
from pathlib import Path
from typing import Callable

FIELDS = (
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
)
LEMMA_PATTERN = re.compile(r"^(.+?)(?:/\d+)?\s*->\s*(.+)$")


def normalized_key(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


def integer(value: str | None) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


def build_database(
    csv_path: Path,
    lemma_path: Path,
    output_path: Path,
    validate_candidate: Callable[[Path], None] | None = None,
) -> dict[str, int]:
    csv_path = Path(csv_path)
    lemma_path = Path(lemma_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, staging_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.",
        suffix=".staging",
        dir=output_path.parent,
    )
    os.close(descriptor)
    staging_path = Path(staging_name)

    database = sqlite3.connect(staging_path)
    try:
        database.executescript(
            """
            PRAGMA page_size = 4096;
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            PRAGMA temp_store = MEMORY;
            CREATE TABLE entries (
                word TEXT NOT NULL COLLATE NOCASE PRIMARY KEY,
                phonetic TEXT NOT NULL DEFAULT '',
                definition TEXT NOT NULL DEFAULT '',
                translation TEXT NOT NULL DEFAULT '',
                pos TEXT NOT NULL DEFAULT '',
                collins INTEGER NOT NULL DEFAULT 0,
                oxford INTEGER NOT NULL DEFAULT 0,
                tag TEXT NOT NULL DEFAULT '',
                bnc INTEGER NOT NULL DEFAULT 0,
                frq INTEGER NOT NULL DEFAULT 0,
                exchange TEXT NOT NULL DEFAULT '',
                detail TEXT NOT NULL DEFAULT '',
                audio TEXT NOT NULL DEFAULT '',
                normalized TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX entries_normalized ON entries(normalized);
            CREATE TABLE lemmas (
                form TEXT NOT NULL COLLATE NOCASE PRIMARY KEY,
                lemma TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE INDEX lemmas_lemma ON lemmas(lemma COLLATE NOCASE);
            """
        )
        insert_entry = """
            INSERT OR REPLACE INTO entries (
                word, phonetic, definition, translation, pos, collins, oxford,
                tag, bnc, frq, exchange, detail, audio, normalized
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if tuple(reader.fieldnames or ()) != FIELDS:
                raise ValueError(f"Unexpected ECDICT fields: {reader.fieldnames!r}")
            batch: list[tuple[object, ...]] = []
            for row in reader:
                word = (row.get("word") or "").strip()
                if not word:
                    continue
                batch.append(
                    (
                        word,
                        row.get("phonetic") or "",
                        row.get("definition") or "",
                        row.get("translation") or "",
                        row.get("pos") or "",
                        integer(row.get("collins")),
                        integer(row.get("oxford")),
                        row.get("tag") or "",
                        integer(row.get("bnc")),
                        integer(row.get("frq")),
                        row.get("exchange") or "",
                        row.get("detail") or "",
                        row.get("audio") or "",
                        normalized_key(word),
                    )
                )
                if len(batch) >= 10_000:
                    database.executemany(insert_entry, batch)
                    batch.clear()
            if batch:
                database.executemany(insert_entry, batch)

        insert_lemma = "INSERT OR IGNORE INTO lemmas(form, lemma) VALUES(?, ?)"
        lemma_batch: list[tuple[str, str]] = []
        with lemma_path.open("r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith(";"):
                    continue
                match = LEMMA_PATTERN.match(line)
                if match is None:
                    raise ValueError(f"Unexpected lemma line: {line!r}")
                lemma = match.group(1).strip()
                for form in match.group(2).split(","):
                    normalized_form = form.strip()
                    if normalized_form and normalized_form.casefold() != lemma.casefold():
                        lemma_batch.append((normalized_form, lemma))
                if len(lemma_batch) >= 10_000:
                    database.executemany(insert_lemma, lemma_batch)
                    lemma_batch.clear()
            if lemma_batch:
                database.executemany(insert_lemma, lemma_batch)

        database.commit()
        database.execute("ANALYZE")
        database.commit()
        check = database.execute("PRAGMA quick_check").fetchone()
        if check is None or check[0] != "ok":
            raise RuntimeError(f"SQLite quick_check failed: {check!r}")
        summary = {
            "entries": database.execute("SELECT COUNT(*) FROM entries").fetchone()[0],
            "lemmas": database.execute("SELECT COUNT(*) FROM lemmas").fetchone()[0],
        }
    except BaseException:
        database.close()
        staging_path.unlink(missing_ok=True)
        raise
    else:
        database.close()

    try:
        os.chmod(staging_path, 0o444)
        if validate_candidate is not None:
            validate_candidate(staging_path)
        os.replace(staging_path, output_path)
    except BaseException:
        staging_path.unlink(missing_ok=True)
        raise
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--lemmas", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    arguments = parser.parse_args()
    from validate_ecdict import validate_database

    def validate(candidate: Path) -> None:
        validate_database(candidate, arguments.manifest)

    summary = build_database(
        arguments.csv,
        arguments.lemmas,
        arguments.output,
        validate_candidate=validate,
    )
    print(f"entries={summary['entries']} lemmas={summary['lemmas']} output={arguments.output}")


if __name__ == "__main__":
    main()
