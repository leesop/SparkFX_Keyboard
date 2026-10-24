#!/bin/bash
set -euo pipefail
APP="${1:?앱 번들 경로가 필요합니다}"
FORBIDDEN="$(find "$APP" \( -iname profiles -o -iname '*.wav' -o -iname '*.mp3' \) -print)"
if [ -n "$FORBIDDEN" ]; then
  echo "배포 금지 리소스가 포함되어 있습니다:" >&2
  echo "$FORBIDDEN" >&2
  exit 1
fi
echo "리소스 검사 통과: profiles / WAV / MP3 없음"
