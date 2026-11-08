#!/bin/bash
# Build libtailscale (official, BSD-3) as a universal static library into vendor/tailscale.
# Needs Go (brew install go). Pinned to a known commit for reproducible builds.
set -euo pipefail
cd "$(dirname "$0")/.."

COMMIT="dacde75057ff350e146505829beff446e6823966"
OUT="vendor/tailscale"
SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT

command -v go >/dev/null || { echo "❌ Go belum terpasang: brew install go"; exit 1; }

echo "→ Ambil libtailscale @ ${COMMIT:0:8}"
git clone -q https://github.com/tailscale/libtailscale.git "$SRC"
git -C "$SRC" checkout -q "$COMMIT"

mkdir -p "$OUT"
for arch in arm64 amd64; do
  clang_arch=$([ "$arch" = arm64 ] && echo arm64 || echo x86_64)
  echo "→ Build $arch"
  ( cd "$SRC" && CGO_ENABLED=1 GOOS=darwin GOARCH=$arch \
      CC="clang -arch $clang_arch -mmacosx-version-min=14.0" CGO_CFLAGS="-mmacosx-version-min=14.0" \
      go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o "libtailscale-$arch.a" . )
done
lipo -create "$SRC/libtailscale-arm64.a" "$SRC/libtailscale-amd64.a" -output "$OUT/libtailscale.a"
cp "$SRC/tailscale.h" "$OUT/tailscale.h"
cp "$SRC/LICENSE" "$OUT/LICENSE"
echo "$COMMIT" > "$OUT/COMMIT"
echo "✅ libtailscale siap di $OUT ($(du -h "$OUT/libtailscale.a" | cut -f1))"
