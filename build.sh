#!/bin/zsh
# Builds an arm64 "Setup for VLC.app" into ./build.
set -euo pipefail
cd "${0:A:h}"
APP="build/Setup for VLC.app"
FLAGS=(-swift-version 5 -target arm64-apple-macos13)

mkdir -p build
swiftc "${FLAGS[@]}" -Onone Sources/VLCRC.swift Tests/main.swift -o build/vlcrc_check
./build/vlcrc_check

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc "${FLAGS[@]}" -O Sources/*.swift -o "$APP/Contents/MacOS/Setup for VLC"
cp Info.plist "$APP/Contents/"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
file "$APP/Contents/MacOS/Setup for VLC"
