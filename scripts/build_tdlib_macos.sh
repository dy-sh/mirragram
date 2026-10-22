#!/usr/bin/env bash
# Builds libtdjson.dylib for macOS.
# Requires: brew install cmake gperf openssl@3
set -euo pipefail

TD_COMMIT="${TD_COMMIT:-c15d3f5a5de6e3ba5839822c451152e5e18bb700}" # TDLib 1.8.68
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tdlib/src"
ARCH="$(uname -m | sed s/x86_64/x64/)"
OUT="$ROOT/.tdlib/out/macos-$ARCH"

if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/tdlib/td.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$TD_COMMIT"

mkdir -p "$SRC/build-macos"
cd "$SRC/build-macos"
cmake -DCMAKE_BUILD_TYPE=Release \
      -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
      -DOPENSSL_USE_STATIC_LIBS=TRUE \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
      ..
cmake --build . --target tdjson -j "$(sysctl -n hw.ncpu)"

mkdir -p "$OUT"
cp -L "$SRC/build-macos/libtdjson.dylib" "$OUT/libtdjson.dylib"
echo "OK: $OUT/libtdjson.dylib"
