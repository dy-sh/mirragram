#!/usr/bin/env bash
# Builds libtdjson.dylib for macOS (current architecture) or iOS (arm64
# devices) with OpenSSL built from source and linked statically.
# Usage: build_tdlib_apple.sh macos|ios
# Requires: Xcode, cmake, gperf (brew install cmake gperf).
set -euo pipefail

PLATFORM="${1:?usage: $0 macos|ios}"
TD_COMMIT="${TD_COMMIT:-c15d3f5a5de6e3ba5839822c451152e5e18bb700}" # TDLib 1.8.68
OPENSSL_VERSION="${OPENSSL_VERSION:-openssl-3.5.4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tdlib/src"
WORK="$ROOT/.tdlib/work-$PLATFORM"
JOBS="$(sysctl -n hw.ncpu)"

case "$PLATFORM" in
  macos)
    ARCH="$(uname -m)"
    OUT="$ROOT/.tdlib/out/macos-${ARCH/x86_64/x64}"
    OPENSSL_TARGET="darwin64-$ARCH-cc"
    MIN_FLAG="-mmacosx-version-min=11.0"
    CMAKE_TARGET=(-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0)
    ;;
  ios)
    OUT="$ROOT/.tdlib/out/ios-arm64"
    OPENSSL_TARGET="ios64-xcrun"
    MIN_FLAG="-mios-version-min=13.0"
    CMAKE_TARGET=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
                  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
    ;;
  *) echo "unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/tdlib/td.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$TD_COMMIT"

OPENSSL="$WORK/openssl"
if [ ! -f "$OPENSSL/lib/libcrypto.a" ]; then
  mkdir -p "$WORK"
  curl -sfL "https://github.com/openssl/openssl/releases/download/$OPENSSL_VERSION/$OPENSSL_VERSION.tar.gz" \
    | tar xz -C "$WORK"
  (cd "$WORK/$OPENSSL_VERSION" &&
    ./Configure "$OPENSSL_TARGET" no-shared no-tests no-apps "$MIN_FLAG" \
      --prefix="$OPENSSL" --libdir=lib &&
    make -j "$JOBS" &&
    make install_sw)
fi

# Cross-compiling needs the generated sources from a native build.
if [ "$PLATFORM" = ios ]; then
  cmake -S "$SRC" -B "$SRC/build-native" -DTD_GENERATE_SOURCE_FILES=ON
  cmake --build "$SRC/build-native" -j "$JOBS"
fi

BUILD="$SRC/build-$PLATFORM"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release "${CMAKE_TARGET[@]}" \
      -DOPENSSL_ROOT_DIR="$OPENSSL" -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build "$BUILD" --target tdjson -j "$JOBS"

mkdir -p "$OUT"
cp -L "$BUILD/libtdjson.dylib" "$OUT/libtdjson.dylib"
install_name_tool -id @rpath/libtdjson.dylib "$OUT/libtdjson.dylib"
echo "OK: $OUT/libtdjson.dylib"
