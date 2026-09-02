#!/usr/bin/env bash
# Builds the executable and assembles a signed NotchDeck.app in build/.
# Prints the bundle path on stdout; everything else goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/NotchDeck.app"

swift build --package-path "$ROOT" -c "$CONFIG" --product notchdeck >&2
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/notchdeck" "$APP/Contents/MacOS/NotchDeck"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="$(security find-identity -v -p codesigning | awk '/NotchDeck Dev/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
    echo "warning: no 'NotchDeck Dev' identity found — signing ad-hoc." >&2
    echo "warning: run Scripts/make-dev-cert.sh so permissions survive rebuilds." >&2
    IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" "$APP" >&2

echo "$APP"
