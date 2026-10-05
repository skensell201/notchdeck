#!/usr/bin/env bash
# Builds the executable and assembles a signed NotchDeck.app in build/.
# Prints the bundle path on stdout; everything else goes to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/NotchDeck.app"
ADAPTER="$ROOT/ThirdParty/mediaremote-adapter"

swift build --package-path "$ROOT" -c "$CONFIG" --product notchdeck >&2
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"
FRAMEWORK="$("$ROOT/Scripts/build-media-adapter.sh")"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/notchdeck" "$APP/Contents/MacOS/NotchDeck"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/StatusIcon.pdf" "$APP/Contents/Resources/"

# The MediaRemote adapter: /usr/bin/perl loads the framework via the .pl script;
# the test client makes the adapter's `test` command a real probe.
cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
cp "$ADAPTER/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp "$ROOT/build/MediaRemoteAdapterTestClient" "$APP/Contents/MacOS/"

IDENTITY="$(security find-identity -v -p codesigning \
  | awk -F'"' '$2 == "NotchDeck Dev" { split($1, f, " "); print f[2]; exit }')"
if [ -z "$IDENTITY" ]; then
    echo "warning: no 'NotchDeck Dev' identity found — signing ad-hoc." >&2
    echo "warning: run Scripts/make-dev-cert.sh so permissions survive rebuilds." >&2
    IDENTITY="-"
fi

# --deep re-signs the nested framework and helper with the same identity; the
# framework must carry a valid signature or perl cannot load it.
codesign --force --deep --sign "$IDENTITY" "$APP" >&2

echo "$APP"
