#!/usr/bin/env bash
# Builds the vendored mediaremote-adapter sources into a code-signed framework
# plus the MediaRemoteAdapterTestClient helper, both under build/.
#
# Upstream builds with CMake; we use clang directly so the only requirement is
# the Xcode toolchain. Things that must stay true:
#   - The framework MUST be signed or /usr/bin/perl cannot dlopen it. Ad-hoc
#     is enough; bundle.sh re-signs it with the app's identity via --deep.
#   - The directory name must match the binary name inside it — the .pl script
#     derives one from the other.
#   - Symbols must be exported (-fvisibility=default) or perl's DynaLoader
#     cannot find adapter_get & co. Upstream's CMakeLists says the same.
#
# Prints the framework path on stdout; everything else goes to stderr.
# Skips the build when the outputs are newer than every vendored source and
# this script; set FORCE=1 to rebuild regardless.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/ThirdParty/mediaremote-adapter"
BUILD="$ROOT/build"
NAME="MediaRemoteAdapter"
OUT="$BUILD/$NAME.framework"
BIN="$OUT/Versions/A/$NAME"
CLIENT="$BUILD/${NAME}TestClient"
ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS="26.0"

up_to_date() {
    [ -f "$BIN" ] && [ -f "$CLIENT" ] || return 1
    for out in "$BIN" "$CLIENT"; do
        [ -z "$(find "$SRC" "${BASH_SOURCE[0]}" -type f -newer "$out" -print -quit)" ] || return 1
    done
}

if [ "${FORCE:-0}" != "1" ] && up_to_date; then
    echo "media adapter up to date: $OUT" >&2
    echo "$OUT"
    exit 0
fi

echo "building $NAME.framework ($ARCH)" >&2
rm -rf "$OUT" "$CLIENT"
mkdir -p "$OUT/Versions/A/Resources" "$OUT/Versions/A/Headers"

# Upstream's source list (CMakeLists.txt: ADAPTER_SOURCES). Sources import
# headers as "adapter/get.h" and "MediaRemoteAdapter.h", hence both -I paths.
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
    -arch "$ARCH" -mmacosx-version-min="$MIN_MACOS" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -compatibility_version 1.0 -current_version 0.7.6 \
    -I "$SRC/include" -I "$SRC/src" \
    -o "$BIN" \
    "$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m

cp "$SRC/include/$NAME.h" "$OUT/Versions/A/Headers/"

cat > "$OUT/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.skensell.notchdeck.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>0.7.6</string>
    <key>CFBundleVersion</key>
    <string>0.7.6</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
</dict>
</plist>
PLIST

ln -sfn A "$OUT/Versions/Current"
ln -sfn "Versions/Current/$NAME" "$OUT/$NAME"
ln -sfn Versions/Current/Resources "$OUT/Resources"
ln -sfn Versions/Current/Headers "$OUT/Headers"

# The test client publishes a fake now-playing entry so the adapter's `test`
# command can prove MediaRemote answers even when nothing is playing.
echo "building ${NAME}TestClient ($ARCH)" >&2
clang -fobjc-arc -O2 \
    -arch "$ARCH" -mmacosx-version-min="$MIN_MACOS" \
    -framework Foundation -framework MediaPlayer \
    -I "$SRC/src/test" \
    -o "$CLIENT" \
    "$SRC"/src/test/main.m "$SRC"/src/test/NowPlayingTest.m

codesign --force --sign - "$OUT" >&2
codesign --force --sign - "$CLIENT" >&2

echo "$OUT"
