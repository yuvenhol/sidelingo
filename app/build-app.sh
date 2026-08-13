#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP="$ROOT/dist/$APP_NAME.app"
SIGNING_IDENTITY="${SIDELINGO_SIGNING_IDENTITY:-SideLingo Local Development}"

cd "$ROOT"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Missing code-signing identity: $SIGNING_IDENTITY" >&2
  echo "Use 'swift build' for an unsigned development binary, or set SIDELINGO_SIGNING_IDENTITY to a valid local identity." >&2
  echo "Refusing to fall back to ad-hoc signing because that invalidates Accessibility authorization." >&2
  exit 1
fi

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
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
