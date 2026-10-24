# Release notes / 릴리스 노트

## 1.2 — Build 5 (2026-10-24)

### English

- Added **Water Droplets**, with three expanding pastel rings and a small landing drop.
- Split visual controls into **Effect Type** (None / Fireworks / Water Droplets) and **Effect Size** (Normal / Large). Existing disabled effects remain disabled.
- Added synthesized **Metal** and **EDM** loop effects.
- Added independent **Electric Guitar** and **Electronic Tones** key effects.
- Rebuilt guitar keys around physically modeled low Drop-D strings, power chords, palm muting, double tracking, and a high-gain amp/cabinet chain.
- Calibrated output headroom and corrected the common key-effect fade so layers fade together when disabled.
- Included Swift source, build/release scripts, and isolated menu/visual/offline-audio tests.

**Requirements:** Apple Silicon, macOS 12+. Launch at Login requires macOS 13+.

**Install:** unzip `SparkFX.Keyboard-1.2-5.zip`, move the app to Applications, allow Accessibility and Input Monitoring, then restart the app. Configure effects from the menu bar icon.

The release is Developer ID signed, Apple notarized, and includes a stapled ticket. Profiles and WAV/MP3 assets are excluded. Built-in sounds are synthesized. Download `SHA256SUMS.txt` alongside the ZIP and verify with:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

### 한국어

- 파스텔 톤 동심원 세 개가 퍼지는 **물방울** 시각 효과를 추가했습니다.
- 시각 메뉴를 **효과 종류**(없음 / 불꽃 / 물방울)와 **효과 크기**(보통 / 크게)로 나눴습니다. 기존 꺼짐 상태를 유지합니다.
- 합성 **메탈·EDM 루프 효과**를 추가했습니다.
- 독립적으로 켜고 끄는 **일렉기타·전자음 키 효과**를 추가했습니다.
- 기타 키 효과를 낮은 드롭 D 현 진동, 파워 코드, 팜뮤트, 더블 트래킹과 하이게인 앰프·캐비닛으로 다시 구성했습니다.
- 출력 헤드룸을 보정하고, 끌 때 키 효과들이 함께 페이드되도록 수정했습니다.
- Swift 소스와 빌드·공증 스크립트, 격리된 메뉴·시각·오프라인 음향 테스트를 포함했습니다.

**실행 환경:** Apple Silicon, macOS 12 이상. 로그인 자동 실행은 macOS 13 이상이 필요합니다.

**설치:** `SparkFX.Keyboard-1.2-5.zip`의 압축을 풀고 앱을 응용 프로그램 폴더로 옮긴 뒤, 손쉬운 접근과 입력 모니터링을 허용하고 앱을 다시 실행하세요. 메뉴 막대 아이콘에서 설정할 수 있습니다.

Developer ID 서명·Apple 공증·티켓 첨부를 완료한 앱입니다. 프로필 폴더와 WAV·MP3 자산은 제외했고 내장 음향은 합성합니다. ZIP과 `SHA256SUMS.txt`를 같은 폴더에 내려받은 뒤 위 명령으로 체크섬을 확인할 수 있습니다.
