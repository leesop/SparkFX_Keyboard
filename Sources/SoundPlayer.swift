import AppKit

/// 고른 소리를 재생한다. 오디오 파일 하나일 수도, Mechvibes 프로필일 수도 있다.
///
/// 파일을 고르면 무슨 키를 누르든 그 소리 하나를 내고,
/// 프로필을 고르면 키마다 프로필이 정한 소리를 낸다.
final class SoundPlayer {
    /// 프로필 안의 파일까지 합쳐 캐시해 두는 재생기 개수 상한.
    private static let fileCacheLimit = 24

    private var profile: SoundProfile?
    private var players: [String: ClickSound] = [:]
    private var order: [String] = []

    /// 지금 올려 둔 경로. 성공했을 때만 바뀐다.
    private(set) var path: String?
    private(set) var displayName = ""

    var isProfile: Bool { profile != nil }

    static func isProfilePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "yaml" || ext == "yml"
    }

    /// 재생할 대상을 바꾼다. 읽지 못하면 false를 돌려주고 아무것도 바꾸지 않는다.
    @discardableResult
    func load(path newPath: String?) -> Bool {
        guard newPath != path else { return true }

        guard let newPath else {
            profile = nil
            displayName = ""
            path = nil
            return true
        }

        if SoundPlayer.isProfilePath(newPath) {
            guard let loaded = SoundProfile.load(at: URL(fileURLWithPath: newPath)), loaded.isUsable else {
                return false
            }
            profile = loaded
            displayName = loaded.name
            path = newPath
            return true
        }

        guard player(for: newPath) != nil else { return false }
        profile = nil
        displayName = SoundSetting.displayName(forPath: newPath)
        path = newPath
        return true
    }

    /// 키에 맞는 소리를 낸다. 파일 하나만 골랐으면 키와 무관하게 그 소리.
    func play(keyCode: UInt16) {
        if let profile {
            playFile(profile.pressFile(forKeyCode: keyCode))
        } else if let path {
            playFile(URL(fileURLWithPath: path))
        }
    }

    /// 마우스 버튼에 맞는 소리를 낸다.
    func play(button: String) {
        if let profile {
            playFile(profile.pressFile(forButton: button))
        } else if let path {
            playFile(URL(fileURLWithPath: path))
        }
    }

    /// 고른 소리를 한 번 들려준다. 프로필이면 space에 해당하는 소리(없으면 기본 소리)가 난다.
    func preview() {
        play(keyCode: 49)
    }

    // MARK: - 파일 재생기 관리

    private func playFile(_ url: URL?) {
        guard let url, let player = player(for: url.path) else { return }
        player.play(volume: Prefs.soundVolume)
    }

    private func player(for filePath: String) -> ClickSound? {
        if let cached = players[filePath] { return cached }

        let player = ClickSound()
        guard player.load(path: filePath) else { return nil }

        players[filePath] = player
        order.append(filePath)
        if order.count > Self.fileCacheLimit {
            players[order.removeFirst()] = nil
        }
        return player
    }
}
