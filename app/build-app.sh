#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/English Companion.app"
SIGNING_IDENTITY="${ENGLISH_COMPANION_SIGNING_IDENTITY:-English Companion Local Development}"

cd "$ROOT"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
  echo "Refusing to fall back to ad-hoc signing because that invalidates Accessibility authorization." >&2
  exit 1
fi

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/EnglishCompanion" "$APP/Contents/MacOS/EnglishCompanion"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"

if [[ "${1:-}" == "--install" ]]; then
  DESTINATION="$HOME/Applications/English Companion.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DESTINATION"
  ditto "$APP" "$DESTINATION"
  echo "$DESTINATION"
  exit 0
fi

echo "$APP"
