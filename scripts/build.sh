#!/bin/sh
# Build the kbglow binary into bin/ for npm packaging.
# Universal (arm64 + x86_64) when the toolchain allows, native otherwise.
set -e
cd "$(dirname "$0")/.."

if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN=.build/apple/Products/Release/kbglow
else
    swift build -c release
    BIN=.build/release/kbglow
fi

mkdir -p bin
cp "$BIN" bin/kbglow
