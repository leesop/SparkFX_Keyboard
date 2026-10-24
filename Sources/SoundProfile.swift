import Foundation

/// Mechvibes 형식 프로필 하나. `profile.yaml`을 읽어 키별 소리를 찾아 준다.
///
/// ```yaml
/// profile: { name: mx-blue, device: keyboard }
/// sources:
///   - id: key1
///     source: { press: press_key1.mp3, release: release.mp3 }
/// keys:
///   default: [ key1, key2 ]
///   other:
///     - sound: space
///       keys: [ space ]
/// ```
struct SoundProfile {
    struct Source {
        let press: String?
        let release: String?
    }

    let name: String
    let isMouseDevice: Bool

    private let directory: URL
    private let sources: [String: Source]
    private let sourceOrder: [String]
    /// 키 이름 / 버튼 이름 -> 소스 id들 (여럿이면 누를 때마다 무작위로 고른다)
    private let keyMap: [String: [String]]
    private let buttonMap: [String: [String]]
    private let defaultKeys: [String]
    private let defaultButtons: [String]

    /// 실제로 재생할 수 있는 소리 파일이 하나라도 있는지.
    /// 파일 이름만 적어 두고 파일이 없는 경우(예: profile.template.yaml)를 걸러 낸다.
    var isUsable: Bool {
        sourceOrder.contains { id in
            guard let entry = sources[id], let file = entry.press ?? entry.release else { return false }
            return FileManager.default.fileExists(atPath: absoluteURL(for: file).path)
        }
    }

    static func load(at url: URL) -> SoundProfile? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let root = MiniYAML.parse(text), case .map = root else { return nil }

        let directory = url.deletingLastPathComponent()
        let block = root.value("profile")
        let name = block?.value("name")?.string ?? directory.lastPathComponent
        let isMouse = block?.value("device")?.string?.lowercased() == "mouse"

        var sources: [String: Source] = [:]
        var order: [String] = []
        for entry in root.value("sources")?.maps ?? [] {
            guard let id = entry["id"]?.string else { continue }
            let source = entry["source"]
            let resolved: Source
            if let single = source?.string {
                resolved = Source(press: single, release: nil)
            } else if let source {
                resolved = Source(
                    press: source.value("press")?.string,
                    release: source.value("release")?.string
                )
            } else {
                continue
            }
            if sources[id] == nil { order.append(id) }
            sources[id] = resolved
        }
        guard !order.isEmpty else { return nil }

        let keys = mapping(in: root.value("keys"))
        let buttons = mapping(in: root.value("buttons"))

        return SoundProfile(
            name: name,
            isMouseDevice: isMouse,
            directory: directory,
            sources: sources,
            sourceOrder: order,
            // `keys`가 없으면 아무 키나 눌렀을 때 전체 소리 중 무작위로 고른다.
            keyMap: keys.map,
            buttonMap: buttons.map,
            defaultKeys: keys.defaults.isEmpty ? order : keys.defaults,
            defaultButtons: buttons.defaults.isEmpty ? order : buttons.defaults
        )
    }

    /// 키코드에 맞는 소리 파일. 매핑이 없으면 프로필의 기본 소리.
    func pressFile(forKeyCode keyCode: UInt16) -> URL? {
        for name in KeyNames.candidates(for: keyCode) {
            if let ids = keyMap[name] { return resolve(ids) }
        }
        return resolve(defaultKeys)
    }

    /// 마우스 버튼에 맞는 소리 파일.
    func pressFile(forButton button: String) -> URL? {
        if let ids = buttonMap[button.lowercased()] { return resolve(ids) }
        return resolve(defaultButtons)
    }

    // MARK: - 읽기 도우미

    private static func mapping(in container: MiniYAML.Value?) -> (defaults: [String], map: [String: [String]]) {
        guard let container else { return ([], [:]) }

        var map: [String: [String]] = [:]
        for entry in container.value("other")?.maps ?? [] {
            let ids = entry["sound"]?.strings ?? []
            guard !ids.isEmpty else { continue }
            for key in entry["keys"]?.strings ?? [] {
                map[key.lowercased()] = ids
            }
            for button in entry["buttons"]?.strings ?? [] {
                map[button.lowercased()] = ids
            }
        }
        return (container.value("default")?.strings ?? [], map)
    }

    /// id 목록에서 하나를 골라 실제 파일 경로로 만든다. 누를 때마다 달라진다.
    private func resolve(_ ids: [String]) -> URL? {
        let usable = ids.filter { sources[$0] != nil }
        guard let id = usable.randomElement(), let source = sources[id] else { return nil }
        // 뗄 때 소리만 있는 소스도 눌렀을 때 대신 쓴다.
        guard let file = source.press ?? source.release else { return nil }
        return absoluteURL(for: file)
    }

    private func absoluteURL(for file: String) -> URL {
        let cleaned = file.hasPrefix("./") ? String(file.dropFirst(2)) : file
        if cleaned.hasPrefix("/") { return URL(fileURLWithPath: cleaned) }
        return directory.appendingPathComponent(cleaned)
    }
}
