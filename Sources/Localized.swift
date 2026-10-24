import Foundation

/// 번역 문자열을 꺼낸다. Resources/<언어>.lproj/Localizable.strings 에서 찾는다.
/// 한국어 기기가 아니면 영어가 나온다 (CFBundleDevelopmentRegion = en).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ argument: String) -> String {
    String(format: NSLocalizedString(key, comment: ""), argument)
}

func L(_ key: String, _ first: String, _ second: String) -> String {
    String(format: NSLocalizedString(key, comment: ""), first, second)
}
