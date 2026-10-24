#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
TMP="$(mktemp -d "$ROOT/build/menu-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/MenuTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/ko.lproj" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.sparkfx.tests</string>
<key>CFBundleExecutable</key><string>MenuTests</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
cat "$ROOT/Sources/AppDelegate.swift" "$ROOT/Tests/MenuChecks.swift" "$ROOT/Tests/ModernAudioChecks.swift" > "$TMP/AppDelegate.swift"
SOURCES=()
for source in "$ROOT/Sources/"*.swift; do
  case "$source" in */main.swift|*/AppDelegate.swift) continue ;; esac
  SOURCES+=("$source")
done
export CLANG_MODULE_CACHE_PATH="$ROOT/build/ModuleCache"
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx12.0"   "${SOURCES[@]}" "$TMP/AppDelegate.swift"   -framework AppKit -framework QuartzCore -framework ApplicationServices   -framework IOKit -framework AVFoundation -framework ServiceManagement   -o "$APP/Contents/MacOS/MenuTests"
for argument in "$@"; do
  if [ "$argument" = "--audio-only" ]; then
    "$APP/Contents/MacOS/MenuTests" "$@"
    exit 0
  fi
done
"$APP/Contents/MacOS/MenuTests" -AppleLanguages '(ko)' "$@"
"$APP/Contents/MacOS/MenuTests" -AppleLanguages '(en)' "$@"
