#!/usr/bin/env bash
# Builds libtdjson.so for Android (arm64-v8a, armeabi-v7a, x86_64) with
# OpenSSL linked statically, using TDLib's example/android scripts.
# Requires: Android SDK with the NDK below, cmake, ninja, gperf, perl, php, JDK.
set -euo pipefail

TD_COMMIT="${TD_COMMIT:-c15d3f5a5de6e3ba5839822c451152e5e18bb700}" # TDLib 1.8.68
OPENSSL_VERSION="${OPENSSL_VERSION:-openssl-3.5.4}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
API_LEVEL=24 # must not exceed the app's minSdk
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?set ANDROID_SDK_ROOT}}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.tdlib/src"

if [ ! -d "$SRC/.git" ]; then
  git clone https://github.com/tdlib/td.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$TD_COMMIT"

cd "$SRC/example/android"
rm -rf third-party/openssl
./build-openssl.sh "$SDK" "$NDK_VERSION" third-party/openssl "$OPENSSL_VERSION"
./build-tdlib.sh "$SDK" "$NDK_VERSION" third-party/openssl c++_static JSON \
  "$API_LEVEL" "arm64-v8a armeabi-v7a x86_64"

for pair in arm64-v8a:arm64 armeabi-v7a:arm x86_64:x64; do
  abi="${pair%%:*}"
  out="$ROOT/.tdlib/out/android-${pair##*:}"
  mkdir -p "$out"
  cp "tdlib/libs/$abi/libtdjson.so" "$out/libtdjson.so"
  echo "OK: $out/libtdjson.so"
done
