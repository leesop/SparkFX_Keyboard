# SparkFX Keyboard

Fireworks, water ripples, and optional sound for your Mac keyboard and mouse.

키보드 입력과 마우스 클릭에 불꽃·물방울 효과와 소리를 더하는 macOS 메뉴 막대 앱입니다.

**[Download / 다운로드](https://github.com/leesop/SparkFX_Keyboard/releases/latest)** · **Version 1.5 / Build 6**

[English](#english) · [한국어](#한국어)

## English

SparkFX Keyboard displays visual effects near the text caret as you type and near the pointer as you click. Choose fireworks or expanding water ripples, synthesize ambient audio, assign your own sounds, or turn typing and clicks into evolving melodies and drum rhythms.

### Installation

- **Apple Silicon (arm64), macOS 12 or later.** This release does not include an Intel build.
- Launch at Login requires macOS 13 or later.
- Download `SparkFX.Keyboard-1.5-6.zip` from [Releases](https://github.com/leesop/SparkFX_Keyboard/releases/latest), unzip it, move **SparkFX Keyboard.app** to **Applications**, and open it.
- The app runs in the menu bar without a Dock icon.
- Official release builds are Developer ID signed, notarized by Apple, and include a stapled notarization ticket.

For keyboard effects, allow **Accessibility** and **Input Monitoring** in **System Settings → Privacy & Security**, then restart the app. The **App Permissions** menu is shown when either permission is missing and hides when both are allowed. Mouse-click effects work without these permissions.

### Visual effects

**Visual Effects → Effect Type:** None / Fireworks (default) / Water Droplets.

**Visual Effects → Effect Size:** Normal (default) / Large.

Water Droplets sends three pastel rings outward from a tiny drop. Keyboard effects are smaller and fainter than mouse effects. Effect type and size are remembered independently; changing size while None is selected keeps effects off.

### Sound

**Click Sound Settings in the menu bar to open the settings window directly.** Choose None (default), Ambient Mode, Custom Sound Mode, Piano Genie, MusicRNN, or Drums Only inside the window. Only one mode is active at a time. Controls take effect immediately and are saved automatically. The window supports resizing and scrolling, and closing it keeps your sound selection.

In **Ambient Mode**:

- **Loop Effects:** Wind & Rain, Warm Pad (default), Metal, EDM, or a loop file you select.
- **Metal:** a synthesized 112 BPM palm-muted power-chord riff.
- **EDM:** a synthesized 128 BPM bass/arpeggio pattern with kick, snare, and hi-hats.
- **Key Effects:** independently toggle Grains, Temple Chimes, Electric Guitar, Electronic Tones, and a 90 BPM Beat. New guitar/electronic effects default to off.
- **Electric Guitar:** low Drop-D power chords using physically modeled plucked strings, independently excited double tracks, pick timing, palm muting, and a high-gain amp/cabinet model. This is synthesized audio, not a recorded guitar sample.
- **Electronic Tones:** short FM-style notes triggered by input.
- **Volume:** 25%, 50% (default), 75%, or 100%, relative to the calibrated output and system volume. It applies to the full mix, including key effects and reverb.

In **Custom Sound Mode**, assign separate keyboard and mouse audio files or Mechvibes-format `profile.yaml` files. Recent selections are remembered. Volume offers the same four steps.

#### AI melody modes

- **Piano Genie:** chooses a note for each keystroke or click using the trained Piano Genie model. Adjust instrument, register, and variation. Optional continuation plays for about 15 seconds after input, then fades out.
- **MusicRNN:** generates an evolving melody conditioned on chords. Adjust instrument, Gentle/Pop/Electronic arrangement, tempo, variation, and automatic accompaniment. Arrangement styles control the chord progression and procedural backing; they are not separately genre-trained models.
- **10 macOS instruments:** piano, electric piano, music box, vibraphone, organ, acoustic guitar, strings, saxophone, flute, and synth lead.
- **Automatic instrument:** randomly selects a different instrument about every four minutes. An overdue change is applied when input resumes after an idle period. It does not require a separate timer while silent.
- Each mode remembers its own options and relative volume: 25%, 50% (default), 75%, or 100%.

#### Drums Only

The MusicRNN-family **DrumsRNN** model generates combinations of kick, snare, hi-hats, toms, and cymbals, played through the macOS system drum kit. No melody, bass, or chord tracks are played.

Choose **Rock / Dance / Half-Time**, rhythm density, and variation. **Follow Input Tempo** is enabled by default: recent input intervals determine a target within 70–160 BPM, applied smoothly at bar boundaries. Turn it off to use the selected base tempo (72 / 90 / 110 / 128 BPM). Styles provide original starter patterns and a stable beat underneath model-generated variations. Audio fades and stops after inactivity.

All three models run locally using Swift and Apple's Accelerate framework. The app does not require Python, a browser, a TensorFlow runtime, runtime model downloads, or an online music service. No typed text is read or sent to a server. Only the selected model is loaded. Model weights total about 18.6 MB; provenance and Apache-2.0 attribution are included in [Resources/Models](Resources/Models/README.md).

**Other Settings** provides Try to Locate the Exact Caret and Launch at Login; both default to off.

### Limitations and included assets

Some apps do not expose a usable caret position, so a fallback is used. Exact-caret support can improve placement in Chromium/Electron apps, at the cost of increased CPU usage in those apps. Secure input fields may prevent keyboard effects.

**No sound-profile folders, WAV files, or MP3 files are included in this repository or the app bundle.** Ambient sounds are synthesized; AI modes use the operating system’s built-in MIDI instruments without bundling a sound bank. Supply your own properly licensed files for custom sounds and file loops.

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
Tests/run.sh --neural-only
```

For your own distribution build, install your own Developer ID certificate and store your own `notarytool` credentials in Keychain. Override the local defaults:

```bash
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' ./release.sh
```

The release script builds, checks excluded resources, notarizes, staples the ticket, verifies Gatekeeper acceptance, and creates a ZIP in `dist/`. **Version 1.5 / build 6 stays fixed unless explicitly changed.** Do not commit signing keys or credentials.

## 한국어

SparkFX Keyboard는 키를 누르면 입력 커서 근처에, 마우스를 클릭하면 포인터 근처에 시각 효과를 표시하는 메뉴 막대 앱입니다. 불꽃·물방울 효과, 합성 앰비언트, 지정 소리와 함께 타건·클릭에 반응하는 AI 멜로디와 드럼 리듬을 사용할 수 있습니다.

### 설치

- **Apple Silicon(arm64), macOS 12 이상**이 필요합니다. 이번 배포 파일에는 Intel용 빌드가 없습니다.
- 로그인 자동 실행은 macOS 13 이상에서 사용할 수 있습니다.
- [릴리스](https://github.com/leesop/SparkFX_Keyboard/releases/latest)에서 `SparkFX.Keyboard-1.5-6.zip`을 내려받아 압축을 풀고 **SparkFX Keyboard.app**을 **응용 프로그램** 폴더로 옮긴 뒤 실행하세요.
- Dock 아이콘 없이 메뉴 막대에서 동작합니다.
- 공식 배포 파일은 Developer ID 서명·Apple 공증·공증 티켓 첨부를 완료한 앱입니다.

키보드 효과를 사용하려면 **시스템 설정 → 개인정보 보호 및 보안**에서 **손쉬운 접근**과 **입력 모니터링**을 허용한 뒤 앱을 다시 실행하세요. 권한이 부족하면 **앱 사용 권한 설정** 메뉴가 표시되고, 모두 허용되면 숨겨집니다. 마우스 클릭 효과는 두 권한 없이 동작합니다.

### 시각 효과

**시각 효과 → 효과 종류:** 없음 / 불꽃(기본값) / 물방울.

**시각 효과 → 효과 크기:** 보통(기본값) / 크게.

물방울은 작은 방울에서 파스텔 톤 동심원 세 개가 퍼지는 효과입니다. 키보드 효과는 마우스 효과보다 작고 옅습니다. 종류와 크기를 따로 기억하며, 없음 상태에서 크기를 바꿔도 효과가 켜지지 않습니다.

### 음향

**메뉴바에서 음향 설정을 한 번 누르면 설정 창이 바로 열립니다.** 창 안에서 없음(기본값), 앰비언트 모드, 사운드 지정 모드, Piano Genie, MusicRNN, 드럼 전용 중 하나를 고릅니다. 변경 사항은 즉시 적용·자동 저장되며 창 크기 조절과 스크롤을 지원합니다. 창을 닫아도 선택한 음향을 유지합니다.

**앰비언트 모드**:

- **루프 효과:** 바람·빗소리, 따뜻한 패드(기본값), 메탈, EDM, 사용자 루프 파일.
- **메탈:** 112 BPM의 팜뮤트 파워 코드 리프를 합성합니다.
- **EDM:** 128 BPM 베이스·아르페지오와 킥·스네어·하이햇을 합성합니다.
- **키 효과:** 알갱이, 산사 풍경, 일렉기타, 전자음, 90 BPM 박자를 각각 켜거나 끌 수 있습니다. 새 기타·전자음 효과는 기본 꺼짐입니다.
- **일렉기타:** 낮은 드롭 D 튜닝의 현 진동·독립된 두 테이크·피킹 시차·팜뮤트를 하이게인 앰프와 캐비닛 모델에 통과시킵니다. 실제 기타 녹음 샘플을 사용하지 않는 합성 음향입니다.
- **전자음:** 입력마다 짧은 FM 방식의 전자음을 냅니다.
- **음량:** 보정된 전체 출력 및 시스템 음량 대비 25% / 50%(기본값) / 75% / 100%. 키 효과와 리버브를 포함한 전체 믹스에 적용됩니다.

**사운드 지정 모드**에서는 키보드와 마우스에 각각 오디오 파일이나 Mechvibes 형식의 `profile.yaml`을 지정할 수 있으며 최근 목록을 기억합니다. 볼륨은 같은 네 단계입니다.

#### AI 멜로디 모드

- **Piano Genie:** 실제 학습 모델이 타건·클릭마다 다음 음을 고릅니다. 기본 악기, 음역, 변주를 조절합니다. 이어 연주를 켜면 입력 후 약 15초간 멜로디를 이어가다가 자연스럽게 잦아듭니다.
- **MusicRNN:** 코드 진행에 맞춰 멜로디를 만듭니다. 기본 악기, 잔잔하게/팝/일렉트로닉 반주 스타일, 템포, 변주와 자동 반주를 고릅니다. 스타일은 코드 진행과 자동 반주의 편곡이며 별도 장르 학습 모델을 뜻하지 않습니다.
- **macOS 기본 악기 10종:** 피아노, 일렉트릭 피아노, 오르골, 비브라폰, 오르간, 어쿠스틱 기타, 스트링, 색소폰, 플루트, 신스 리드.
- **자동 악기:** 약 4분마다 직전과 다른 악기로 무작위 전환합니다. 쉬는 동안 전환 시각이 지났다면 다음 입력 때 새 악기로 바뀌며, 무음 상태에서 별도 타이머를 돌리지 않습니다.
- 각 모드의 옵션과 상대 음량 25% / 50%(기본값) / 75% / 100%를 따로 기억합니다.

#### 드럼 전용

MusicRNN 계열의 **DrumsRNN**이 킥·스네어·하이햇·탐·심벌 조합을 생성하고 macOS 기본 드럼으로 연주합니다. 멜로디·베이스·코드 반주는 재생하지 않습니다.

**록 / 댄스 / 하프타임**, 리듬 밀도와 변주를 조절할 수 있습니다. **입력 템포 따라가기**는 기본 켜짐이며 최근 입력 간격을 바탕으로 70~160 BPM 범위에서 마디마다 부드럽게 조절합니다. 끄면 선택한 기준 템포(72 / 90 / 110 / 128 BPM)를 유지합니다. 직접 만든 시작 패턴과 기본 박자를 모델의 변주와 결합하며 입력이 멈추면 잦아든 뒤 정지합니다.

세 모델 모두 Swift와 Apple Accelerate로 로컬에서 실행합니다. Python, 브라우저, TensorFlow 실행 환경, 실행 중 모델 다운로드나 온라인 음악 서비스를 필요로 하지 않습니다. 입력 내용을 읽거나 서버로 보내지 않습니다. 선택한 모델만 불러오며 가중치는 총 약 18.6MB입니다. 출처와 Apache-2.0 표기는 [Resources/Models](Resources/Models/README.md)에 포함했습니다.

**기타 설정**에는 정확한 커서 취득 시도와 로그인시 자동 실행이 있으며, 기본값은 모두 꺼짐입니다.

### 제약과 포함 자산

일부 앱에서는 정확한 커서 좌표를 얻지 못해 대체 위치에 효과를 표시합니다. 정확한 커서 취득 기능은 Chromium/Electron 앱에서 위치 정확도를 높일 수 있지만 해당 앱의 CPU 사용량이 늘 수 있습니다. 보안 입력이 켜진 입력란에서는 키보드 효과가 동작하지 않을 수 있습니다.

**이 저장소와 앱 번들에는 사운드 프로필 폴더와 WAV·MP3 파일을 포함하지 않습니다.** 앰비언트는 직접 합성하고 AI 모드는 별도 사운드 뱅크를 넣지 않고 운영체제의 기본 MIDI 악기로 연주합니다. 사운드 지정과 루프 파일은 사용 권한이 있는 파일을 직접 선택해 주세요.

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
Tests/run.sh --neural-only
```

배포용 빌드는 본인의 Developer ID 인증서와 키체인의 공증 인증 정보를 준비한 뒤, 위 영어 예시처럼 `SIGNING_IDENTITY`와 `NOTARY_PROFILE`을 지정해 `release.sh`를 실행하세요. 서명 키와 인증 정보는 커밋하지 마세요. **버전 1.5 / 빌드 6는 명시적으로 변경할 때까지 유지합니다.**
