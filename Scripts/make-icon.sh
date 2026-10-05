#!/usr/bin/env bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns, and the menu bar
# template Resources/StatusIcon.svg into Resources/StatusIcon.pdf.
#
# The icons are drawn as SVG rather than checked in as a binary blob nobody can
# edit: a tweak is a diff. Run this after changing either SVG, then commit
# the regenerated .icns and .pdf alongside. Needs rsvg-convert (`brew install librsvg`).
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

# Vector, so the menu bar draws it sharp at any scale. At 72 dpi one SVG unit is
# one point, which makes the 18-unit canvas an 18-point glyph.
STATUS="$ROOT/Resources/StatusIcon.pdf"
rsvg-convert -f pdf --dpi-x 72 --dpi-y 72 "$ROOT/Resources/StatusIcon.svg" -o "$STATUS"
echo "$STATUS"
