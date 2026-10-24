# SparkFX Keyboard

Fireworks, water ripples, and optional sound for your Mac keyboard and mouse.

키보드 입력과 마우스 클릭에 불꽃·물방울 효과와 소리를 더하는 macOS 메뉴 막대 앱입니다.

**[Download / 다운로드](https://github.com/leesop/SparkFX_Keyboard/releases/latest)** · **Version 1.2 / Build 5**

[English](#english) · [한국어](#한국어)

## English

SparkFX Keyboard displays visual effects near the text caret as you type and near the pointer as you click. Choose fireworks or expanding water ripples, add synthesized ambient audio, or assign your own keyboard and mouse sounds.

### Installation

- **Apple Silicon (arm64), macOS 12 or later.** This release does not include an Intel build.
- Launch at Login requires macOS 13 or later.
- Download `SparkFX.Keyboard-1.2-5.zip` from [Releases](https://github.com/leesop/SparkFX_Keyboard/releases/latest), unzip it, move **SparkFX Keyboard.app** to **Applications**, and open it.
- The app runs in the menu bar without a Dock icon.
- Official release builds are Developer ID signed, notarized by Apple, and include a stapled notarization ticket.

For keyboard effects, allow **Accessibility** and **Input Monitoring** in **System Settings → Privacy & Security**, then restart the app. The **App Permissions** menu is shown when either permission is missing and hides when both are allowed. Mouse-click effects work without these permissions.

### Visual effects

**Visual Effects → Effect Type:** None / Fireworks (default) / Water Droplets.

**Visual Effects → Effect Size:** Normal (default) / Large.

Water Droplets sends three pastel rings outward from a tiny drop. Keyboard effects are smaller and fainter than mouse effects. Effect type and size are remembered independently; changing size while None is selected keeps effects off.

### Sound

**Sound Settings → Sound Type:** None (default), Ambient Mode, or Custom Sound Mode. Only one sound mode is active at a time. **Sound Options** opens a separate submenu for the selected mode.

In **Ambient Mode**:

- **Loop Effects:** Wind & Rain, Warm Pad (default), Metal, EDM, or a loop file you select.
- **Metal:** a synthesized 112 BPM palm-muted power-chord riff.
- **EDM:** a synthesized 128 BPM bass/arpeggio pattern with kick, snare, and hi-hats.
- **Key Effects:** independently toggle Grains, Temple Chimes, Electric Guitar, Electronic Tones, and a 90 BPM Beat. New guitar/electronic effects default to off.
- **Electric Guitar:** low Drop-D power chords using physically modeled plucked strings, independently excited double tracks, pick timing, palm muting, and a high-gain amp/cabinet model. This is synthesized audio, not a recorded guitar sample.
- **Electronic Tones:** short FM-style notes triggered by input.
- **Volume:** 25%, 50% (default), 75%, or 100%, relative to the calibrated output and system volume. It applies to the full mix, including key effects and reverb.

In **Custom Sound Mode**, assign separate keyboard and mouse audio files or Mechvibes-format `profile.yaml` files. Recent selections are remembered. Volume offers the same four steps.

**Other Settings** provides Try to Locate the Exact Caret and Launch at Login; both default to off.

### Limitations and included assets

Some apps do not expose a usable caret position, so a fallback is used. Exact-caret support can improve placement in Chromium/Electron apps, at the cost of increased CPU usage in those apps. Secure input fields may prevent keyboard effects.

**No sound-profile folders, WAV files, or MP3 files are included in this repository or the app bundle.** Built-in sounds are synthesized. Supply your own properly licensed files for custom sounds and file loops.

### Build from source

The Swift/AppKit source builds directly with `swiftc`; no Xcode project is required. Install Xcode or the Xcode command-line tools.

```bash
# Local ad-hoc build, without a Developer ID certificate:
SIGNING_IDENTITY=- ./build.sh
open "build/SparkFX Keyboard.app"

# Rebuild only when source changes, then launch:
SIGNING_IDENTITY=- ./run.sh

# Isolated menu/visual/audio checks; audio is rendered offline:
Tests/run.sh
Tests/run.sh --audio-only
```

For your own distribution build, install your own Developer ID certificate and store your own `notarytool` credentials in Keychain. Override the local defaults:

```bash
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' ./release.sh
```

The release script builds, checks excluded resources, notarizes, staples the ticket, verifies Gatekeeper acceptance, and creates a ZIP in `dist/`. **Version 1.2 / build 5 stays fixed unless explicitly changed.** Do not commit signing keys or credentials.

## 한국어

SparkFX Keyboard는 키를 누르면 입력 커서 근처에, 마우스를 클릭하면 포인터 근처에 시각 효과를 표시하는 메뉴 막대 앱입니다. 불꽃·물방울 효과, 합성 앰비언트, 직접 지정한 키보드·마우스 소리를 사용할 수 있습니다.

### 설치

- **Apple Silicon(arm64), macOS 12 이상**이 필요합니다. 이번 배포 파일에는 Intel용 빌드가 없습니다.
- 로그인 자동 실행은 macOS 13 이상에서 사용할 수 있습니다.
- [릴리스](https://github.com/leesop/SparkFX_Keyboard/releases/latest)에서 `SparkFX.Keyboard-1.2-5.zip`을 내려받아 압축을 풀고 **SparkFX Keyboard.app**을 **응용 프로그램** 폴더로 옮긴 뒤 실행하세요.
- Dock 아이콘 없이 메뉴 막대에서 동작합니다.
- 공식 배포 파일은 Developer ID 서명·Apple 공증·공증 티켓 첨부를 완료한 앱입니다.

키보드 효과를 사용하려면 **시스템 설정 → 개인정보 보호 및 보안**에서 **손쉬운 접근**과 **입력 모니터링**을 허용한 뒤 앱을 다시 실행하세요. 권한이 부족하면 **앱 사용 권한 설정** 메뉴가 표시되고, 모두 허용되면 숨겨집니다. 마우스 클릭 효과는 두 권한 없이 동작합니다.

### 시각 효과

**시각 효과 → 효과 종류:** 없음 / 불꽃(기본값) / 물방울.

**시각 효과 → 효과 크기:** 보통(기본값) / 크게.

물방울은 작은 방울에서 파스텔 톤 동심원 세 개가 퍼지는 효과입니다. 키보드 효과는 마우스 효과보다 작고 옅습니다. 종류와 크기를 따로 기억하며, 없음 상태에서 크기를 바꿔도 효과가 켜지지 않습니다.

### 음향

**음향 설정 → 음향 종류:** 없음(기본값) / 앰비언트 모드 / 사운드 지정 모드. 한 번에 한 모드만 활성화됩니다. **음향 옵션**은 선택한 모드의 옵션을 하위 메뉴로 표시합니다.

**앰비언트 모드**:

- **루프 효과:** 바람·빗소리, 따뜻한 패드(기본값), 메탈, EDM, 사용자 루프 파일.
- **메탈:** 112 BPM의 팜뮤트 파워 코드 리프를 합성합니다.
- **EDM:** 128 BPM 베이스·아르페지오와 킥·스네어·하이햇을 합성합니다.
- **키 효과:** 알갱이, 산사 풍경, 일렉기타, 전자음, 90 BPM 박자를 각각 켜거나 끌 수 있습니다. 새 기타·전자음 효과는 기본 꺼짐입니다.
- **일렉기타:** 낮은 드롭 D 튜닝의 현 진동·독립된 두 테이크·피킹 시차·팜뮤트를 하이게인 앰프와 캐비닛 모델에 통과시킵니다. 실제 기타 녹음 샘플을 사용하지 않는 합성 음향입니다.
- **전자음:** 입력마다 짧은 FM 방식의 전자음을 냅니다.
- **음량:** 보정된 전체 출력 및 시스템 음량 대비 25% / 50%(기본값) / 75% / 100%. 키 효과와 리버브를 포함한 전체 믹스에 적용됩니다.

**사운드 지정 모드**에서는 키보드와 마우스에 각각 오디오 파일이나 Mechvibes 형식의 `profile.yaml`을 지정할 수 있으며 최근 목록을 기억합니다. 볼륨은 같은 네 단계입니다.

**기타 설정**에는 정확한 커서 취득 시도와 로그인시 자동 실행이 있으며, 기본값은 모두 꺼짐입니다.

### 제약과 포함 자산

일부 앱에서는 정확한 커서 좌표를 얻지 못해 대체 위치에 효과를 표시합니다. 정확한 커서 취득 기능은 Chromium/Electron 앱에서 위치 정확도를 높일 수 있지만 해당 앱의 CPU 사용량이 늘 수 있습니다. 보안 입력이 켜진 입력란에서는 키보드 효과가 동작하지 않을 수 있습니다.

**이 저장소와 앱 번들에는 사운드 프로필 폴더와 WAV·MP3 파일을 포함하지 않습니다.** 내장 음향은 직접 합성합니다. 사운드 지정과 루프 파일은 사용 권한이 있는 파일을 직접 선택해 주세요.

### 소스 빌드

Swift/AppKit 소스를 `swiftc`로 직접 빌드하며 Xcode 프로젝트는 필요하지 않습니다. Xcode 또는 Xcode 명령줄 도구가 필요합니다.

```bash
# Developer ID 인증서가 없는 로컬 빌드:
SIGNING_IDENTITY=- ./build.sh
open "build/SparkFX Keyboard.app"

# 변경된 경우에만 빌드 후 실행:
SIGNING_IDENTITY=- ./run.sh

# 격리된 설정으로 메뉴·시각·음향 검사 (스피커 출력 없음):
Tests/run.sh
Tests/run.sh --audio-only
```

배포용 빌드는 본인의 Developer ID 인증서와 키체인의 공증 인증 정보를 준비한 뒤, 위 영어 예시처럼 `SIGNING_IDENTITY`와 `NOTARY_PROFILE`을 지정해 `release.sh`를 실행하세요. 서명 키와 인증 정보는 커밋하지 마세요. **버전 1.2 / 빌드 5는 명시적으로 변경할 때까지 유지합니다.**
