#!/usr/bin/env bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
#
# The icon is drawn as an SVG rather than checked in as a binary blob nobody can
# edit: a tweak is a diff. Run this after changing the SVG, then commit the
# regenerated .icns alongside. Needs rsvg-convert (`brew install librsvg`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
OUT="$ROOT/Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found — brew install librsvg" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"

for pt in 16 32 128 256 512; do
    rsvg-convert -w "$pt" -h "$pt" "$SVG" -o "$ICONSET/icon_${pt}x${pt}.png"
    rsvg-convert -w "$((pt * 2))" -h "$((pt * 2))" "$SVG" -o "$ICONSET/icon_${pt}x${pt}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "$OUT"
