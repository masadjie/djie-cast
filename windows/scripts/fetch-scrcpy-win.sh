#!/bin/bash
# Unduh scrcpy resmi (Genymobile) untuk Windows, cek SHA-256, taruh di src-tauri/resources/scrcpy.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="5.0.1"
SHA="b12a2c4ee8be317422451fc7dcf8ee20a71b5ea7ef9ad73ddd825a25316227a5"
NAME="scrcpy-win64-v${VERSION}"
DEST="src-tauri/resources/scrcpy"

if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$VERSION" ]; then
  echo "✅ scrcpy $VERSION sudah ada"; exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "→ Unduh $NAME.zip"
curl -fsSL -o "$TMP/s.zip" "https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}/${NAME}.zip"
if command -v shasum >/dev/null; then SUM="shasum -a 256"; else SUM="sha256sum"; fi
echo "$SHA  $TMP/s.zip" | $SUM -c
unzip -q "$TMP/s.zip" -d "$TMP"
rm -rf "$DEST" && mkdir -p "$DEST"
cp "$TMP/$NAME"/*.exe "$TMP/$NAME"/*.dll "$TMP/$NAME/scrcpy-server" "$TMP/$NAME/scrcpy.png" "$DEST/"
cp "$TMP/$NAME/LICENSE.txt" "$DEST/LICENSE.txt"
echo "$VERSION" > "$DEST/VERSION"
echo "✅ scrcpy $VERSION (Windows) siap di $DEST"
