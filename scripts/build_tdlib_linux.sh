#!/usr/bin/env bash
# Builds libtdjson.so for Linux (current architecture) with OpenSSL linked
# statically.
# Requires: apt install cmake gperf g++ libssl-dev zlib1g-dev
set -euo pipefail

TD_COMMIT="${TD_COMMIT:-c15d3f5a5de6e3ba5839822c451152e5e18bb700}" # TDLib 1.8.68
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tdlib/src"
ARCH="$(uname -m | sed -e s/x86_64/x64/ -e s/aarch64/arm64/)"
OUT="$ROOT/.tdlib/out/linux-$ARCH"

if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/tdlib/td.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$TD_COMMIT"

BUILD="$SRC/build-linux"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build "$BUILD" --target tdjson -j "$(nproc)"

mkdir -p "$OUT"
cp -L "$BUILD/libtdjson.so" "$OUT/libtdjson.so"
strip --strip-unneeded "$OUT/libtdjson.so"
echo "OK: $OUT/libtdjson.so"
