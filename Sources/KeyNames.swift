import AppKit

/// macOS 가상 키코드를 프로필이 쓰는 키 이름으로 옮긴다.
///
/// 프로필마다 표기가 조금씩 달라서(`capslock`/`caps_lock`, `shift`/`shift_l`, `delete`/`backspace`)
/// 한 키에 후보 이름을 여러 개 두고 앞에서부터 맞춰 본다.
enum KeyNames {
    static func candidates(for keyCode: UInt16) -> [String] {
        table[keyCode] ?? []
    }

    private static let table: [UInt16: [String]] = [
        // 글자
        0: ["a"], 11: ["b"], 8: ["c"], 2: ["d"], 14: ["e"], 3: ["f"], 5: ["g"], 4: ["h"],
        34: ["i"], 38: ["j"], 40: ["k"], 37: ["l"], 46: ["m"], 45: ["n"], 31: ["o"], 35: ["p"],
        12: ["q"], 15: ["r"], 1: ["s"], 17: ["t"], 32: ["u"], 9: ["v"], 13: ["w"], 7: ["x"],
        16: ["y"], 6: ["z"],

        // 숫자
        29: ["0"], 18: ["1"], 19: ["2"], 20: ["3"], 21: ["4"], 23: ["5"],
        22: ["6"], 26: ["7"], 28: ["8"], 25: ["9"],

        // 기호
        27: ["minus", "-"], 24: ["equal", "="], 33: ["left_bracket", "["],
        30: ["right_bracket", "]"], 42: ["backslash", "\\"], 41: ["semicolon", ";"],
        39: ["quote", "'"], 43: ["comma", ","], 47: ["period", "."], 44: ["slash", "/"],
        50: ["grave", "`"],

        // 특수 키
        36: ["enter", "return"], 76: ["enter", "return"],
        48: ["tab"], 49: ["space"], 53: ["escape", "esc"],
        51: ["backspace", "delete"], 117: ["delete", "backspace"],
        57: ["caps_lock", "capslock"],
        56: ["shift_l", "shift"], 60: ["shift_r", "shift"],
        59: ["ctrl_l", "ctrl"], 62: ["ctrl_r", "ctrl"],
        58: ["alt_l", "alt", "option"], 61: ["alt_r", "alt_gr", "alt", "option"],
        55: ["cmd", "command", "meta"], 54: ["command_r", "cmd", "command"],
        63: ["fn", "function"],

        // 이동
        123: ["left", "arrow_left"], 124: ["right", "arrow_right"],
        125: ["down", "arrow_down"], 126: ["up", "arrow_up"],
        115: ["home"], 119: ["end"], 116: ["page_up", "pageup"], 121: ["page_down", "pagedown"],
        114: ["insert", "help"],

        // 숫자 패드
        71: ["clear"], 81: ["equal"], 75: ["slash"], 67: ["asterisk"], 78: ["minus"], 69: ["plus"],
        82: ["0"], 83: ["1"], 84: ["2"], 85: ["3"], 86: ["4"], 87: ["5"], 88: ["6"],
        89: ["7"], 91: ["8"], 92: ["9"], 65: ["period"],

        // 펑션 키
        122: ["f1"], 120: ["f2"], 99: ["f3"], 118: ["f4"], 96: ["f5"], 97: ["f6"],
        98: ["f7"], 100: ["f8"], 101: ["f9"], 109: ["f10"], 103: ["f11"], 111: ["f12"],
        105: ["f13"], 107: ["f14"], 113: ["f15"],
    ]

    /// 마우스 버튼 이름. 프로필의 `buttons`에 쓰이는 표기.
    static func buttonName(for event: NSEvent.EventType) -> String? {
        switch event {
        case .leftMouseDown: return "left"
        case .rightMouseDown: return "right"
        case .otherMouseDown: return "middle"
        default: return nil
        }
    }
}
