import csv
import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "build_ecdict.py"


class BuildECDICTTests(unittest.TestCase):
    def test_builds_queryable_read_only_database_with_lemmas(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv_path = root / "ecdict.csv"
            lemma_path = root / "lemma.en.txt"
            output_path = root / "ecdict.sqlite"
            with csv_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=[
                        "word", "phonetic", "definition", "translation", "pos",
                        "collins", "oxford", "tag", "bnc", "frq", "exchange",
                        "detail", "audio",
                    ],
                )
                writer.writeheader()
                writer.writerow({
                    "word": "relocate",
                    "phonetic": "ri:ləʊ'keɪt",
                    "definition": "move to a new place",
                    "translation": "搬迁；重新安置",
                    "pos": "v:100",
                    "collins": "2",
                    "oxford": "1",
                    "tag": "cet6 ielts",
                    "bnc": "7342",
                    "frq": "5981",
                    "exchange": "d:relocated/p:relocated",
                    "detail": '{"example":"We relocated."}',
                    "audio": "",
                })
                writer.writerow({
                    "word": "keep me posted",
                    "translation": "随时告诉我最新进展",
                    "frq": "1200",
                })
            lemma_path.write_text(
                "; fixture\nrelocate/42 -> relocated,relocates,relocating\n'hood -> 'hoods\n",
                encoding="utf-8",
            )

            module = load_builder()
            summary = module.build_database(csv_path, lemma_path, output_path)

            self.assertEqual(summary["entries"], 2)
            self.assertEqual(summary["lemmas"], 4)
            database = sqlite3.connect(f"file:{output_path}?mode=ro", uri=True)
            self.addCleanup(database.close)
            self.assertEqual(database.execute("PRAGMA quick_check").fetchone()[0], "ok")
            row = database.execute(
                "SELECT translation, collins, oxford, detail FROM entries WHERE word = ? COLLATE NOCASE",
                ("RELOCATE",),
            ).fetchone()
            self.assertEqual(row, ("搬迁；重新安置", 2, 1, '{"example":"We relocated."}'))
            self.assertEqual(
                database.execute("SELECT lemma FROM lemmas WHERE form = ?", ("relocated",)).fetchone()[0],
                "relocate",
            )
            self.assertEqual(
                database.execute("SELECT word FROM entries WHERE normalized = ?", ("keepmeposted",)).fetchone()[0],
                "keep me posted",
            )
            with self.assertRaises(sqlite3.OperationalError):
                database.execute("DELETE FROM entries")

    def test_builder_keeps_secure_mkstemp_file_until_sqlite_opens_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv_path, lemma_path = write_minimal_sources(root)
            output_path = root / "ecdict.sqlite"
            module = load_builder()
            original_connect = module.sqlite3.connect
            observed = []

            def checked_connect(path, *args, **kwargs):
                candidate = Path(path)
                observed.append(candidate.is_file() and not candidate.is_symlink())
                return original_connect(path, *args, **kwargs)

            with mock.patch.object(module.sqlite3, "connect", side_effect=checked_connect):
                module.build_database(csv_path, lemma_path, output_path)

            self.assertEqual(observed, [True])

    def test_candidate_validation_failure_preserves_previous_database(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv_path, lemma_path = write_minimal_sources(root)
            output_path = root / "ecdict.sqlite"
            module = load_builder()
            module.build_database(csv_path, lemma_path, output_path)
            previous = output_path.read_bytes()

            def reject(_candidate):
                raise ValueError("manifest validation failed")

            with self.assertRaisesRegex(ValueError, "manifest validation failed"):
                module.build_database(
                    csv_path,
                    lemma_path,
                    output_path,
                    validate_candidate=reject,
                )

            self.assertEqual(output_path.read_bytes(), previous)

    def test_publish_failure_preserves_previous_database(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv_path = root / "ecdict.csv"
            lemma_path = root / "lemma.en.txt"
            output_path = root / "ecdict.sqlite"
            with csv_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(module_fields()))
                writer.writeheader()
                writer.writerow({"word": "safe", "translation": "安全"})
            lemma_path.write_text("; fixture\n", encoding="utf-8")
            module = load_builder()
            module.build_database(csv_path, lemma_path, output_path)
            previous = output_path.read_bytes()

            with mock.patch.object(module.os, "replace", side_effect=OSError("publish failed")):
                with self.assertRaisesRegex(OSError, "publish failed"):
                    module.build_database(csv_path, lemma_path, output_path)

            self.assertTrue(output_path.exists())
            self.assertEqual(output_path.read_bytes(), previous)


def write_minimal_sources(root: Path) -> tuple[Path, Path]:
    csv_path = root / "ecdict.csv"
    lemma_path = root / "lemma.en.txt"
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(module_fields()))
        writer.writeheader()
        writer.writerow({"word": "safe", "translation": "安全"})
    lemma_path.write_text("; fixture\n", encoding="utf-8")
    return csv_path, lemma_path


def module_fields():
    return (
        "word", "phonetic", "definition", "translation", "pos", "collins",
        "oxford", "tag", "bnc", "frq", "exchange", "detail", "audio",
    )


def load_builder():
    spec = importlib.util.spec_from_file_location("build_ecdict", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load build_ecdict.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


if __name__ == "__main__":
    unittest.main()
