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

# Ad-hoc sign the (possibly fat) binary as a whole. The per-slice linker
# signatures are not a valid signature for the universal file, and TCC
# (Full Disk Access for watch mode) refuses to match an unsigned binary
# against its recorded requirement.
codesign --force -s - -i dev.totota08.kbglow bin/kbglow
