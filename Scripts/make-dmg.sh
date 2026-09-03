#!/usr/bin/env bash
# Builds a release NotchDeck.app and wraps it in a compressed disk image.
#
# The image is not notarized: notarization needs a paid Developer ID, and the
# vendored MediaRemote adapter's whole technique is an end-run around a private
# framework, so the App Store was never a destination either. A first launch
# needs a right-click and Open; the README says so.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING="$ROOT/build/dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/NotchDeck-$VERSION.dmg"

APP="$(CONFIG=release "$ROOT/Scripts/bundle.sh")"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "NotchDeck $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >&2

rm -rf "$STAGING"
echo "$DMG"
