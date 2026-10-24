import AppKit
import Foundation

/// 무엇이 불꽃을 터뜨렸는지. 입력마다 효과 크기와 소리를 따로 두기 위해 쓴다.
enum Trigger: Int, CaseIterable {
    case keyboard = 0
    case mouse = 1

    var titleKey: String {
        switch self {
        case .keyboard: return "menu.sound.keyboard"
        case .mouse: return "menu.sound.mouse"
        }
    }

    /// 마우스 화살표가 차지하는 만큼 커서 옆으로 밀어야 해서, 키보드 쪽은 조금 작게 잡는다.
    var sizeFactor: CGFloat {
        switch self {
        case .keyboard: return 0.75
        case .mouse: return 1.0
        }
    }

    /// 키보드는 글자 바로 옆에서 터져 가독성을 해치므로 더 옅게 그린다.
    var opacityFactor: CGFloat {
        switch self {
        case .keyboard: return 0.7
        case .mouse: return 1.0
        }
    }
}

enum VisualEffect: String, CaseIterable {
    case none, fireworks, ripple

    var title: String { L("visual.kind.\(rawValue)") }
}

enum EffectSize: String, CaseIterable {
    case large
    case medium
    case small
    case off

    var titleKey: String {
        switch self {
        case .large: return "effect.large"
        case .medium: return "effect.medium"
        case .small: return "effect.small"
        case .off: return "effect.off"
        }
    }

    var title: String { L(titleKey) }

    var style: SparkStyle? {
        switch self {
        case .large: return SparkStyle(scale: 0.175, speed: 110, count: 240, lifetime: 1.05, gravity: 75, opacity: 0.6)
        case .medium: return SparkStyle(scale: 0.125, speed: 82, count: 170, lifetime: 0.85, gravity: 60, opacity: 0.6)
        case .small: return SparkStyle(scale: 0.09, speed: 60, count: 110, lifetime: 0.65, gravity: 45, opacity: 0.6)
        case .off: return nil
        }
    }
}

struct SparkStyle: Equatable {
    /// 파티클 하나의 크기 (pt)
    var scale: CGFloat
    /// 터질 때 튀어나가는 속도 (pt/s)
    var speed: CGFloat
    /// 한 번에 터지는 파티클 수
    var count: Float
    /// 수명 (초)
    var lifetime: Float
    /// 아래로 떨어지는 가속도 (pt/s²)
    var gravity: CGFloat
    /// 파티클 하나의 불투명도. 겹치면 진해지므로 낮게 잡아야 뒤의 글자가 비친다.
    var opacity: CGFloat

    /// 파티클을 한동안 방출한 뒤 끊는다. 짧을수록 한 점에서 동시에 터진 것처럼 보인다.
    static let burstDuration: Float = 0.07

    /// 입력에 맞춘 사본. 키보드는 더 작고 더 옅게 그린다.
    /// 퍼지는 반경과 낙하도 크기에 맞춰 줄여 모양을 유지한다.
    func adjusted(for trigger: Trigger) -> SparkStyle {
        SparkStyle(
            scale: scale * trigger.sizeFactor,
            speed: speed * trigger.sizeFactor,
            count: count,
            lifetime: lifetime,
            gravity: gravity * trigger.sizeFactor,
            opacity: opacity * trigger.opacityFactor
        )
    }
}

/// 입력 하나에 딸린 소리 설정.
struct SoundSetting: Equatable {
    /// 사용자가 고른 파일. nil이면 아직 고른 적이 없다.
    var path: String?
    /// 꺼 두어도 고른 파일은 기억한다.
    var isEnabled: Bool

    var fileName: String? {
        path.map { SoundSetting.displayName(forPath: $0) }
    }

    /// 메뉴에 보여 줄 이름.
    /// 프로필은 관례상 `<이름>/profile.yaml`이라 파일 이름이 쓸모없어서 폴더 이름을 쓴다.
    static func displayName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard SoundPlayer.isProfilePath(path) else { return url.lastPathComponent }
        let base = url.deletingPathExtension().lastPathComponent
        return base.lowercased() == "profile" ? url.deletingLastPathComponent().lastPathComponent : base
    }

    /// 실제로 재생할 파일. 꺼져 있거나 고른 파일이 없으면 nil.
    var activePath: String? {
        isEnabled ? path : nil
    }
}

enum SoundMode: String, CaseIterable {
    case off, ambient, custom, pianoGenie, musicRNN, drumsRNN

    var titleKey: String { "sound.mode.\(rawValue)" }
}

enum Prefs {
    static var defaults = UserDefaults.standard
    private static let effectSizeKey = "effectSize"
    private static let visualEffectKey = "visual.effect"
    private static let noticeKey = "hasShownPermissionNotice"
    private static let volumeKey = "sound.volume"
    /// 소리 목록에 보여 줄 최대 개수. 길어지면 메뉴가 지저분해진다.
    private static let recentLimit = 8

    static var effectSize: EffectSize {
        get {
            guard let raw = defaults.string(forKey: effectSizeKey) else { return .small }
            let size = EffectSize(rawValue: raw) ?? .small
            switch size {
            case .large: return .medium
            case .off: return .small
            default: return size
            }
        }
        set {
            // Persist the legacy off state before overwriting its old size key.
            visualEffect = newValue == .off ? .none : visualEffect
            defaults.set(newValue == .off ? EffectSize.small.rawValue : newValue.rawValue, forKey: effectSizeKey)
        }
    }

    static var visualEffect: VisualEffect {
        get {
            if let raw = defaults.string(forKey: visualEffectKey), let effect = VisualEffect(rawValue: raw) {
                return effect
            }
            return defaults.string(forKey: effectSizeKey) == EffectSize.off.rawValue ? .none : .fireworks
        }
        set { defaults.set(newValue.rawValue, forKey: visualEffectKey) }
    }

    /// 손쉬운 접근 권한 안내 창을 이미 보여줬는지. 매번 띄우면 성가시다.
    static var hasShownPermissionNotice: Bool {
        get { defaults.bool(forKey: noticeKey) }
        set { defaults.set(newValue, forKey: noticeKey) }
    }

    static func soundKey(_ trigger: Trigger, _ field: String) -> String {
        "sound.\(trigger == .keyboard ? "keyboard" : "mouse").\(field)"
    }

    static func sound(_ trigger: Trigger) -> SoundSetting {
        let defaults = Self.defaults
        return SoundSetting(
            path: defaults.string(forKey: soundKey(trigger, "path")),
            isEnabled: defaults.bool(forKey: soundKey(trigger, "enabled"))
        )
    }

    /// 최근에 고른 소리 파일들. 앞에 있을수록 최근이다.
    static func recentSounds(_ trigger: Trigger) -> [String] {
        defaults.stringArray(forKey: soundKey(trigger, "recent")) ?? []
    }

    /// 고른 파일을 목록 맨 앞으로 올린다. 같은 파일이 이미 있으면 위로 끌어올린다.
    static func noteUsedSound(_ trigger: Trigger, path: String) {
        var list = recentSounds(trigger)
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        defaults.set(Array(list.prefix(recentLimit)), forKey: soundKey(trigger, "recent"))
    }

    static func removeRecentSound(_ trigger: Trigger, path: String) {
        var list = recentSounds(trigger)
        list.removeAll { $0 == path }
        defaults.set(list, forKey: soundKey(trigger, "recent"))
    }

    static func clearRecentSounds(_ trigger: Trigger) {
        defaults.removeObject(forKey: soundKey(trigger, "recent"))
    }

    static func setSound(_ trigger: Trigger, _ setting: SoundSetting) {
        let defaults = Self.defaults
        defaults.set(setting.path, forKey: soundKey(trigger, "path"))
        defaults.set(setting.isEnabled, forKey: soundKey(trigger, "enabled"))
    }

    /// 소리 크기. 0.0~1.0.
    static var soundVolume: Float {
        get {
            guard defaults.object(forKey: volumeKey) != nil else { return 0.5 }
            return nearestVolume(defaults.float(forKey: volumeKey))
        }
        set { defaults.set(newValue, forKey: volumeKey) }
    }

    static let volumeOptions: [Float] = [0.25, 0.5, 0.75, 1.0]

    private static func nearestVolume(_ value: Float) -> Float {
        volumeOptions.min { abs($0 - value) < abs($1 - value) } ?? 0.5
    }

    /// Existing installations keep the previously active sound category.
    /// A new installation starts silent.
    static var soundMode: SoundMode {
        get {
            if let raw = defaults.string(forKey: "sound.mode"), let mode = SoundMode(rawValue: raw) {
                return mode
            }
            if defaults.bool(forKey: ambientEnabledKey) { return .ambient }
            if Trigger.allCases.contains(where: { sound($0).activePath != nil }) { return .custom }
            return .off
        }
        set { defaults.set(newValue.rawValue, forKey: "sound.mode") }
    }

    // MARK: - 앰비언트

    private static let ambientVoiceKey = "ambient.voice"
    private static let ambientEnabledKey = "ambient.enabled"
    private static let ambientLevelKey = "ambient.maxLevel"

    static var ambientVoice: AmbientVoice {
        get {
            guard let raw = defaults.string(forKey: ambientVoiceKey) else { return .pad }
            return AmbientVoice.fromStoredValue(raw)
        }
        set { defaults.set(newValue.storedValue, forKey: ambientVoiceKey) }
    }

    /// 앰비언트 전체 출력에 적용하는 시스템 음량 대비 비율.
    static var ambientMaxLevel: Float {
        get {
            guard defaults.object(forKey: ambientLevelKey) != nil else { return 0.5 }
            return nearestVolume(defaults.float(forKey: ambientLevelKey))
        }
        set { defaults.set(newValue, forKey: ambientLevelKey) }
    }

    static let ambientLevelOptions = volumeOptions

    private static let ambientGrainsKey = "ambient.grains"
    private static let ambientChimesKey = "ambient.chimes"
    private static let ambientBPMKey = "ambient.bpm"

    /// 입력마다 음 하나를 띄우는 알갱이를 쓸지.
    static var ambientGrains: Bool {
        get { defaults.bool(forKey: ambientGrainsKey) }
        set { defaults.set(newValue, forKey: ambientGrainsKey) }
    }

    static var ambientGuitar: Bool {
        get { defaults.bool(forKey: "ambient.guitar") }
        set { defaults.set(newValue, forKey: "ambient.guitar") }
    }

    static var ambientElectronic: Bool {
        get { defaults.bool(forKey: "ambient.electronic") }
        set { defaults.set(newValue, forKey: "ambient.electronic") }
    }

    private static let accurateCaretKey = "accurateCaret"

    /// 커서 좌표를 알려주지 않는 앱(Chromium/Electron)에서 접근성 트리를 켜서 정확한 커서를 얻을지.
    /// VoiceOver가 켜는 것과 같은 스위치라 그 앱의 CPU 사용이 늘어난다. 그래서 기본은 꺼짐.
    static var accurateCaret: Bool {
        get { defaults.bool(forKey: accurateCaretKey) }
        set { defaults.set(newValue, forKey: accurateCaretKey) }
    }

    /// 어떤 음색 위에도 처마 풍경 소리를 얹을지.
    static var ambientChimes: Bool {
        get { defaults.bool(forKey: ambientChimesKey) }
        set { defaults.set(newValue, forKey: ambientChimesKey) }
    }

    /// 배경을 맥동시킬 박자. 0이면 박자 없음.
    static var ambientBPM: Float {
        get { defaults.float(forKey: ambientBPMKey) > 0 ? 90 : 0 }
        set { defaults.set(newValue, forKey: ambientBPMKey) }
    }

}
