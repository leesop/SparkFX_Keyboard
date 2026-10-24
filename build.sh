#!/bin/bash
# SparkFX Keyboard.app 빌드: 아이콘 생성 → 컴파일 → 앱 번들 구성 → 임시 서명
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
export CLANG_MODULE_CACHE_PATH="$BUILD/ModuleCache"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Jae Gwang Lee (7MX7T85U7H)}"
APP="$BUILD/SparkFX Keyboard.app"
CONTENTS="$APP/Contents"

echo "==> 1/5 불꽃 아이콘 생성"
rm -rf "$APP" "$BUILD/AppIcon.iconset"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$BUILD/AppIcon.iconset"

swiftc -O -swift-version 5 \
  "$ROOT/Tools/IconGen.swift" "$ROOT/Sources/FireworkShape.swift" \
  -o "$BUILD/icongen"
"$BUILD/icongen" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> 2/5 번역 리소스 복사"
for lproj in "$ROOT/Resources/"*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$CONTENTS/Resources/"
done

echo "==> 3/5 컴파일"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx12.0" -whole-module-optimization \
  "$ROOT/Sources/"*.swift \
  -framework AppKit -framework QuartzCore -framework ApplicationServices -framework IOKit -framework AVFoundation -framework ServiceManagement \
  -o "$CONTENTS/MacOS/SparkFX Keyboard"

echo "==> 4/5 Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>SparkFX Keyboard</string>
	<key>CFBundleExecutable</key>
	<string>SparkFX Keyboard</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.sparkkey.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>SparkFX Keyboard</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.2</string>
	<key>CFBundleVersion</key>
	<string>5</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 leesop.com</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> 5/5 리소스 검사 및 서명"
"$ROOT/verify-resources.sh" "$APP"
if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier "com.sparkkey.app" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier "com.sparkkey.app" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "완료: $APP"
echo "실행: open \"$APP\""
