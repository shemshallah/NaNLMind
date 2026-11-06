#!/bin/sh
set -eu
arch="${1:-native}"
case "$arch" in
  x86_64|linux-x86_64) build="build/linux-x86_64" ;;
  aarch64|linux-aarch64) build="build/linux-aarch64" ;;
  android-arm64) build="build/android-arm64" ;;
  native) build="build/native" ;;
  *) echo "usage: $0 [native|x86_64|aarch64|android-arm64]" >&2; exit 2 ;;
esac
make -j2 BUILD="$build" "$@"
