# SparkFX Keyboard

Fireworks and optional sound for your Mac keyboard and mouse.  
Mac에서 키보드 입력과 마우스 클릭에 불꽃 효과와 소리를 더하는 메뉴 막대 앱입니다.

**[Download / 다운로드](https://github.com/leesop/SparkFX_Keyboard/releases/latest)** · **Version 1.0 / Build 4**

[English](#english) · [한국어](#한국어)

## English

SparkFX Keyboard is a macOS menu bar app that displays a burst of particles near the text caret when you type, or at the pointer when you click. Optional ambient audio and custom keyboard/mouse sounds add another layer of feedback.

### Requirements and installation

- Apple Silicon Mac (arm64), macOS 12 or later. This release does not include an Intel build.
- Launch at Login requires macOS 13 or later.
- Download `SparkFX.Keyboard-1.0-4.zip` from [Releases](https://github.com/leesop/SparkFX_Keyboard/releases/latest), unzip it, move **SparkFX Keyboard.app** to **Applications**, and open it.
- The app runs in the menu bar and does not show a Dock icon.
- The release is signed with Developer ID, notarized by Apple, and includes a stapled notarization ticket. Gatekeeper verification passed for this build.

### Permissions

For keyboard effects, enable **Accessibility** and **Input Monitoring** in **System Settings → Privacy & Security**, then restart the app. The **App Permissions** menu shows permission status and links to settings; it disappears once both permissions are granted. Mouse-click effects work without these two permissions.

### Features and defaults

- **Visual Effect Settings:** None, Normal (default), or Large. Keyboard particles are smaller and fainter than mouse particles.
- **Sound Settings → Sound Type:** None (default), Ambient Mode, or Custom Sound Mode. Only one sound mode is active at a time.
- **Sound Settings → Sound Options:** a submenu containing options for the selected sound mode; disabled when the sound type is None.
- **Ambient Mode:** synthesized Wind & Rain or Warm Pad (default), or a loop file you select. Toggle Grains, Temple Chimes, and a 90 BPM Beat independently.
- **Custom Sound Mode:** choose separate keyboard and mouse audio files or Mechvibes-format `profile.yaml` files. Recent selections are remembered.
- **Volume:** 25%, 50% (default), 75%, or 100%, relative to the system output volume. Ambient volume controls the complete mix, including key effects and reverb.
- **Other Settings:** Try to Locate the Exact Caret and Launch at Login (both off by default).
- Settings and selected file paths are remembered between launches.

### Notes

Some apps do not expose a usable text-caret position. The app uses a fallback position in those cases. **Try to Locate the Exact Caret** can improve placement in Chromium/Electron apps, but may increase their CPU usage. Secure input fields may prevent keyboard effects.

**No sound profiles, WAV files, or MP3 files are bundled with the release.** Synthesized ambient sounds work without external audio assets. Supply your own properly licensed audio or profiles for custom sounds and file loops. This repository provides release builds and documentation.

## 한국어

SparkFX Keyboard는 키를 누르면 입력 커서 근처에서, 마우스를 클릭하면 포인터 위치에서 불꽃 파티클을 터뜨리는 macOS 메뉴 막대 앱입니다. 앰비언트와 직접 지정한 키보드·마우스 소리를 선택적으로 사용할 수 있습니다.

### 실행 환경과 설치

- Apple Silicon Mac(arm64), macOS 12 이상이 필요합니다. 이번 릴리스에는 Intel용 빌드가 포함되지 않습니다.
- 로그인 자동 실행은 macOS 13 이상에서 사용할 수 있습니다.
- [릴리스](https://github.com/leesop/SparkFX_Keyboard/releases/latest)에서 `SparkFX.Keyboard-1.0-4.zip`을 내려받아 압축을 풀고, **SparkFX Keyboard.app**을 **응용 프로그램** 폴더로 옮긴 뒤 실행합니다.
- 앱은 메뉴 막대에서 실행되며 Dock 아이콘은 표시하지 않습니다.
- Developer ID 서명, Apple 공증, 공증 티켓 첨부를 완료했으며 해당 빌드의 Gatekeeper 검증을 통과했습니다.

### 권한 설정

키보드 효과를 사용하려면 **시스템 설정 → 개인정보 보호 및 보안**에서 **손쉬운 접근**과 **입력 모니터링**을 허용한 뒤 앱을 다시 실행하세요. **앱 사용 권한 설정** 메뉴에서 상태를 확인하고 설정을 열 수 있으며, 두 권한이 모두 허용되면 이 메뉴는 숨겨집니다. 마우스 클릭 효과는 두 권한 없이도 동작합니다.

### 주요 기능과 기본값

- **시각 효과 설정:** 없음 / 보통(기본값) / 크게. 키보드 불꽃은 마우스 불꽃보다 작고 옅습니다.
- **음향 설정 → 음향 종류:** 없음(기본값) / 앰비언트 모드 / 사운드 지정 모드. 한 번에 한 모드만 활성화됩니다.
- **음향 설정 → 음향 옵션:** 선택한 모드의 옵션을 한 단계 아래 하위 메뉴에 표시합니다. 음향 종류가 없음이면 비활성화됩니다.
- **앰비언트 모드:** 직접 합성하는 바람·빗소리, 따뜻한 패드(기본값), 또는 사용자가 지정한 루프 파일을 사용합니다. 알갱이·산사 풍경·90 BPM 박자를 각각 켜거나 끌 수 있습니다.
- **사운드 지정 모드:** 키보드와 마우스에 각각 오디오 파일이나 Mechvibes 형식의 `profile.yaml`을 지정할 수 있습니다. 최근 파일 목록을 기억합니다.
- **음량:** 시스템 출력 음량 대비 25% / 50%(기본값) / 75% / 100%. 앰비언트 음량은 키 효과와 리버브를 포함한 전체 믹스에 적용됩니다.
- **기타 설정:** 정확한 커서 취득 시도, 로그인시 자동 실행. 두 기능 모두 기본값은 꺼짐입니다.
- 앱을 다시 실행해도 설정과 선택한 파일 경로를 기억합니다.

### 참고 사항

일부 앱은 입력 커서 위치를 제공하지 않아 대체 위치에 불꽃이 표시될 수 있습니다. **정확한 커서 취득 시도**를 켜면 Chromium/Electron 앱에서 위치 정확도를 높일 수 있지만 해당 앱의 CPU 사용량이 늘 수 있습니다. 보안 입력이 켜진 입력란에서는 키보드 효과가 동작하지 않을 수 있습니다.

**배포 파일에는 사운드 프로필 폴더와 WAV·MP3 파일을 포함하지 않습니다.** 합성 앰비언트는 외부 음원 없이 사용할 수 있습니다. 사운드 지정과 루프 파일은 사용 권한을 확보한 파일을 직접 선택해 주세요. 이 저장소에는 배포 빌드와 설명 문서를 제공합니다.
