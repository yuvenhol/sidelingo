#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP="$ROOT/dist/$APP_NAME.app"
ECDICT_RESOURCE="$ROOT/Resources/ECDICT/ecdict.sqlite"
ECDICT_MANIFEST="$ROOT/Resources/ECDICT/MANIFEST.json"
SIGNING_IDENTITY="${SIDELINGO_SIGNING_IDENTITY:-SideLingo Local Development}"

cd "$ROOT"

if [[ ! -f "$ECDICT_RESOURCE" ]]; then
  echo "Missing generated ECDICT resource: $ECDICT_RESOURCE" >&2
  echo "Run './scripts/prepare-ecdict.sh' before packaging SideLingo." >&2
  exit 1
fi
python3 "$ROOT/scripts/validate_ecdict.py" \
  --database "$ECDICT_RESOURCE" \
  --manifest "$ECDICT_MANIFEST"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
  echo "Use 'swift build' for an unsigned development binary, or set SIDELINGO_SIGNING_IDENTITY to a valid local identity." >&2
  echo "Refusing to fall back to ad-hoc signing because that invalidates Accessibility authorization." >&2
  exit 1
fi

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ECDICT"
cp "$ROOT/.build/release/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
cp "$ECDICT_RESOURCE" "$APP/Contents/Resources/ECDICT/ecdict.sqlite"
cp "$ROOT/Resources/ECDICT/LICENSE" "$APP/Contents/Resources/ECDICT/LICENSE"
cp "$ROOT/Resources/ECDICT/ATTRIBUTION.md" "$APP/Contents/Resources/ECDICT/ATTRIBUTION.md"
cp "$ECDICT_MANIFEST" "$APP/Contents/Resources/ECDICT/MANIFEST.json"
python3 "$ROOT/scripts/validate_ecdict.py" \
  --database "$APP/Contents/Resources/ECDICT/ecdict.sqlite" \
  --manifest "$APP/Contents/Resources/ECDICT/MANIFEST.json"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"

if [[ "${1:-}" == "--install" ]]; then
  DESTINATION="$HOME/Applications/$APP_NAME.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DESTINATION"
  ditto "$APP" "$DESTINATION"
  echo "$DESTINATION"
  exit 0
fi

echo "$APP"
