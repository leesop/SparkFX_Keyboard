#!/bin/bash
# Developer ID 서명 → 공증 → 티켓 첨부 → 배포 ZIP 생성
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Jae Gwang Lee (7MX7T85U7H)}"
APP="$ROOT/build/SparkFX Keyboard.app"
DIST="$ROOT/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-kiss-notary}"
"$ROOT/build.sh"
"$ROOT/verify-resources.sh" "$APP"
mkdir -p "$DIST"
if [ -z "${NOTARY_PROFILE:-}" ]; then
  echo "서명 완료. 공증에는 NOTARY_PROFILE(키체인에 저장한 notarytool 프로필명)이 필요합니다." >&2
  exit 1
fi
UPLOAD="$ROOT/build/notarization-upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
RESULT="$ROOT/build/notarization-result.json"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$RESULT"
if ! /usr/bin/plutil -extract status raw -o - "$RESULT" | /usr/bin/grep -qx Accepted; then
  cat "$RESULT" >&2
  echo "공증 실패: notarytool log로 상세 정보를 확인하세요." >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
"$ROOT/verify-resources.sh" "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
ZIP="$DIST/SparkFX Keyboard-$VERSION-$BUILD_NUMBER.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "공증된 배포 파일: $ZIP"
