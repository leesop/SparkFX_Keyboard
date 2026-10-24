# Release notes / 릴리스 노트

## 1.5 — Build 6 (2026-10-24)

### English

- Added **Piano Genie**, **MusicRNN**, and **Drums Only** with real, locally executed pretrained note-generation models.
- **Sound Settings** now opens a standalone settings window directly from the menu bar. All options apply immediately and are remembered independently per mode.
- Expanded to **10 macOS system instruments** plus **Automatic**, which switches to a different instrument about every four minutes.
- Extended optional Piano Genie continuation to about **15 seconds**, followed by a gentle fade.
- **Drums Only** uses the MusicRNN-family DrumsRNN model. Choose Rock/Dance/Half-Time, density and variation; follow typing speed or select a fixed base tempo. Only drum channels play.
- Added native Swift/Accelerate inference, numerical comparisons against TensorFlow.js, and offline playback, tempo, volume, mode-switch and bilingual UI checks.

**Requirements:** Apple Silicon (arm64), macOS 12+. Launch at Login requires macOS 13+.

**Install/update:** quit the old app, unzip `SparkFX.Keyboard-1.5-6.zip`, and move **SparkFX Keyboard.app** to Applications, replacing the older copy. Existing preferences are retained. For keyboard input, allow Accessibility and Input Monitoring and restart the app if requested.

The app is Developer ID signed, Apple notarized, and includes a stapled ticket. Models run offline, with about 18.6 MB of bundled note-generation weights; no instrument sound bank, profiles, WAV, or MP3 files are included. AI playback uses macOS built-in MIDI instruments. Model provenance and Apache-2.0 attribution are included in the source and app resources.

Download the ZIP and `SHA256SUMS.txt` together and verify with:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

### 한국어

- 실제 사전 학습 모델을 로컬에서 실행하는 **Piano Genie·MusicRNN·드럼 전용** 모드를 추가했습니다.
- 메뉴바의 **음향 설정**을 클릭하면 독립 설정 창이 바로 열립니다. 각 옵션은 즉시 적용되고 모드별로 저장됩니다.
- **macOS 기본 악기 10종**과 약 4분마다 다른 악기로 바뀌는 **자동** 선택을 제공합니다.
- Piano Genie의 선택적 이어 연주를 약 **15초**로 늘리고 자연스럽게 잦아들도록 했습니다.
- **드럼 전용**은 MusicRNN 계열 DrumsRNN으로 리듬을 생성합니다. 록·댄스·하프타임, 밀도·변주를 조절하고, 입력 속도를 따라가거나 기준 템포를 고를 수 있습니다. 드럼만 연주합니다.
- Swift/Accelerate 추론과 원본 TensorFlow.js 수치 대조, 오프라인 연주·템포·음량·모드 전환·한영 UI 검증을 추가했습니다.

**실행 환경:** Apple Silicon(arm64), macOS 12 이상. 로그인 자동 실행은 macOS 13 이상입니다.

**설치/업데이트:** 기존 앱을 종료하고 `SparkFX.Keyboard-1.5-6.zip`을 푼 뒤 **SparkFX Keyboard.app**을 응용 프로그램 폴더의 기존 앱과 교체하세요. 기존 설정은 유지됩니다. 키보드 입력에 필요한 손쉬운 접근·입력 모니터링 권한을 확인하고 안내가 있으면 다시 실행하세요.

Developer ID 서명·Apple 공증·티켓 첨부를 완료한 앱입니다. 모델은 오프라인으로 동작하며 음표 생성 가중치 약 18.6MB만 포함합니다. 악기 사운드 뱅크·프로필·WAV·MP3는 포함하지 않고 macOS 기본 MIDI 악기로 연주합니다. 모델 출처와 Apache-2.0 표기를 소스와 앱 리소스에 포함했습니다.

ZIP과 `SHA256SUMS.txt`를 함께 내려받아 위 명령으로 체크섬을 확인할 수 있습니다.

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
