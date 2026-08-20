import csv
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


class ValidateECDICTTests(unittest.TestCase):
    def test_validates_digest_schema_counts_and_representative_queries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database_path = build_fixture_database(root)
            manifest_path = write_manifest(root, database_path)
            validator = load_module("validate_ecdict", SCRIPTS / "validate_ecdict.py")

            summary = validator.validate_database(database_path, manifest_path)

            self.assertEqual(summary["entries"], 1)
            self.assertEqual(summary["lemmas"], 1)

    def test_rejects_database_whose_digest_does_not_match_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database_path = build_fixture_database(root)
            manifest_path = write_manifest(root, database_path)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["database_sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            validator = load_module("validate_ecdict", SCRIPTS / "validate_ecdict.py")

            with self.assertRaisesRegex(Exception, "SHA-256"):
                validator.validate_database(database_path, manifest_path)


def build_fixture_database(root: Path) -> Path:
    csv_path = root / "ecdict.csv"
    lemma_path = root / "lemma.en.txt"
    database_path = root / "ecdict.sqlite"
    fields = (
        "word", "phonetic", "definition", "translation", "pos", "collins",
        "oxford", "tag", "bnc", "frq", "exchange", "detail", "audio",
    )
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fields))
        writer.writeheader()
        writer.writerow({"word": "relocate", "translation": "搬迁"})
    lemma_path.write_text("relocate/1 -> relocated\n", encoding="utf-8")
    builder = load_module("build_ecdict", SCRIPTS / "build_ecdict.py")
    builder.build_database(csv_path, lemma_path, database_path)
    return database_path


def write_manifest(root: Path, database_path: Path) -> Path:
    digest = hashlib.sha256(database_path.read_bytes()).hexdigest()
    manifest = {
        "schema_version": 1,
        "source": {
            "commit": "fixture",
            "archive_sha256": "a" * 64,
            "csv_sha256": "b" * 64,
            "lemma_sha256": "c" * 64,
        },
        "database_sha256": digest,
        "entries": 1,
        "lemmas": 1,
        "representative_entries": {"relocate": "搬迁"},
        "representative_lemmas": {"relocated": "relocate"},
    }
    path = root / "MANIFEST.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    return path


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == "__main__":
    unittest.main()
