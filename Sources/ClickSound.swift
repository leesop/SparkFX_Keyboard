import AppKit

/// 입력할 때 재생할 소리. 같은 소리를 빠르게 연달아 내도 서로 끊기지 않도록
/// 여러 개를 돌려 쓴다.
final class ClickSound {
    private let poolSize = 4
    private var pool: [NSSound] = []
    private var next = 0
    private(set) var path: String?

    var isLoaded: Bool { !pool.isEmpty }

    /// 재생할 파일을 바꾼다. 같은 파일이면 그대로 둔다.
    /// 읽지 못하는 파일이면 false를 돌려준다.
    @discardableResult
    func load(path newPath: String?) -> Bool {
        guard newPath != path else { return true }
        path = newPath
        pool = []
        next = 0

        guard let newPath else { return true }

        // byReference가 실패하는 형식도 있어 한 번 더 시도한다.
        let loaded = (0..<poolSize).compactMap { _ in
            NSSound(contentsOfFile: newPath, byReference: true)
                ?? NSSound(contentsOfFile: newPath, byReference: false)
        }
        guard loaded.count == poolSize else {
            path = nil
            pool = []
            return false
        }
        pool = loaded
        return true
    }

    func play(volume: Float) {
        guard !pool.isEmpty else { return }
        let sound = pool[next]
        next = (next + 1) % pool.count
        sound.volume = volume
        sound.stop()
        sound.play()
    }
}
