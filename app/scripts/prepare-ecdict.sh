#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
CACHE="$ROOT/.cache/ecdict"
ARCHIVE="$CACHE/stardict.7z"
CSV="$CACHE/stardict.csv"
LEMMAS="$CACHE/lemma.en.txt"
OUTPUT="$ROOT/Resources/ECDICT/ecdict.sqlite"
MANIFEST="$ROOT/Resources/ECDICT/MANIFEST.json"
ARCHIVE_SHA256="f370a0ecb58ada758d9dfe739db1667fd4ed87ed3055a4a7cb6c7054ecdf83d6"
CSV_SHA256="88fce01e0a30524192a62e363d47eeb036fa17820d5826121b3b419fd67a3996"
LEMMA_SHA256="e255b097404e3e0052060e2ddf6e15a1414f577071d63d51d2ca0ce9dacee0fc"

mkdir -p "$CACHE" "$(dirname "$OUTPUT")"

fetch() {
  local name="$1"
  local destination="$2"
  local expected="$3"
  if [[ ! -f "$destination" ]] || [[ "$(shasum -a 256 "$destination" | cut -d' ' -f1)" != "$expected" ]]; then
    curl -L --fail --retry 3 --show-error \
      "https://raw.githubusercontent.com/skywind3000/ECDICT/$PIN/$name" \
      -o "$destination.download"
    mv "$destination.download" "$destination"
  fi
  local actual
  actual="$(shasum -a 256 "$destination" | cut -d' ' -f1)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for $name: expected $expected, got $actual" >&2
    exit 1
  fi
}

fetch "stardict.7z" "$ARCHIVE" "$ARCHIVE_SHA256"
fetch "lemma.en.txt" "$LEMMAS" "$LEMMA_SHA256"

if [[ ! -f "$CSV" ]] || [[ "$(shasum -a 256 "$CSV" | cut -d' ' -f1)" != "$CSV_SHA256" ]]; then
  if ! command -v bsdtar >/dev/null 2>&1; then
    echo "bsdtar is required to extract the pinned ECDICT archive." >&2
    exit 1
  fi
  bsdtar -xOf "$ARCHIVE" stardict.csv > "$CSV.download"
  mv "$CSV.download" "$CSV"
fi
if [[ "$(shasum -a 256 "$CSV" | cut -d' ' -f1)" != "$CSV_SHA256" ]]; then
  echo "Checksum mismatch for extracted stardict.csv" >&2
  exit 1
fi

needs_build=0
if [[ "${1:-}" == "--force" ]]; then
  needs_build=1
elif ! python3 "$ROOT/scripts/validate_ecdict.py" \
  --database "$OUTPUT" \
  --manifest "$MANIFEST" >/dev/null 2>&1; then
  needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
  python3 "$ROOT/scripts/build_ecdict.py" \
    --csv "$CSV" \
    --lemmas "$LEMMAS" \
    --output "$OUTPUT" \
    --manifest "$MANIFEST"
fi

python3 "$ROOT/scripts/validate_ecdict.py" \
  --database "$OUTPUT" \
  --manifest "$MANIFEST"
