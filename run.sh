#!/bin/bash
# 빌드 후 실행. 인자는 앱에 그대로 전달된다. (예: ./run.sh --demo)
# 소스가 바뀌지 않았으면 다시 빌드하지 않는다. --rebuild 를 주면 강제로 다시 빌드한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/SparkFX Keyboard.app"
BINARY="$APP/Contents/MacOS/SparkFX Keyboard"
ARGS=()

force=0
for argument in "$@"; do
  if [ "$argument" = "--rebuild" ]; then
    force=1
  else
    ARGS+=("$argument")
  fi
done

needs_build() {
  [ "$force" = "1" ] && return 0
  [ -x "$BINARY" ] || return 0
  # 앱이 만들어진 뒤에 소스가 바뀌었는지 본다.
  [ -n "$(find "$ROOT/Sources" "$ROOT/Tools" "$ROOT/Resources" "$ROOT/build.sh" "$ROOT/verify-resources.sh" -newer "$BINARY" -print -quit 2>/dev/null)" ]
}

if needs_build; then
  "$ROOT/build.sh"
  # 실행 중이던 인스턴스는 예전 실행 파일을 붙들고 있다.
  if pgrep -f "SparkFX Keyboard.app/Contents/MacOS/SparkFX Keyboard" >/dev/null; then
    pkill -f "SparkFX Keyboard.app/Contents/MacOS/SparkFX Keyboard" || true
    sleep 1
  fi
else
  echo "==> 변경 없음. 이미 빌드된 앱을 실행합니다. (강제로 다시 빌드하려면 --rebuild)"
fi

if [ ${#ARGS[@]} -gt 0 ]; then
  open "$APP" --args "${ARGS[@]}"
else
  open "$APP"
fi
