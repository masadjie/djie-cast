#!/bin/bash
# Unduh scrcpy resmi (Genymobile) untuk macOS, cek SHA-256, lalu gabung jadi universal di vendor/scrcpy.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="5.0.1"
SHA_ARM="33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b"
SHA_X86="31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50"
BASE="https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for arch in aarch64 x86_64; do
  f="scrcpy-macos-${arch}-v${VERSION}.tar.gz"
  echo "→ Unduh $f"
  curl -fsSL -o "$TMP/$f" "$BASE/$f"
done
( cd "$TMP"
  printf '%s  %s\n%s  %s\n' "$SHA_ARM" "scrcpy-macos-aarch64-v${VERSION}.tar.gz" \
                            "$SHA_X86" "scrcpy-macos-x86_64-v${VERSION}.tar.gz" | shasum -a 256 -c
  for f in *.tar.gz; do tar -xzf "$f"; done )

A="$TMP/scrcpy-macos-aarch64-v${VERSION}"
X="$TMP/scrcpy-macos-x86_64-v${VERSION}"
rm -rf vendor/scrcpy && mkdir -p vendor/scrcpy
lipo -create "$A/scrcpy" "$X/scrcpy" -output vendor/scrcpy/scrcpy
cp "$A/adb" "$A/scrcpy-server" "$A/scrcpy.png" "$A/disconnected.png" "$A/LICENSE" vendor/scrcpy/
echo "$VERSION" > vendor/scrcpy/VERSION
chmod +x vendor/scrcpy/scrcpy vendor/scrcpy/adb
echo "✅ scrcpy $VERSION siap di vendor/scrcpy"
