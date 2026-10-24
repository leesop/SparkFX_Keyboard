import Foundation

/// Mechvibes 프로필에 쓰이는 만큼만 지원하는 최소 YAML 읽기.
///
/// 지원: 중첩 map, 블록 목록(`- 값`), 인라인 목록(`[ a, b ]`), 스칼라, 주석, 따옴표, BOM.
/// 지원하지 않음: 여러 줄 문자열, 앵커/별칭, 탭 들여쓰기, 복잡한 스칼라 타입.
enum MiniYAML {
    indirect enum Value {
        case scalar(String)
        case list([Value])
        case map([String: Value])

        var string: String? {
            if case .scalar(let value) = self { return value }
            return nil
        }

        func value(_ key: String) -> Value? {
            if case .map(let entries) = self { return entries[key] }
            return nil
        }

        /// 스칼라 하나, 또는 스칼라 목록을 문자열 배열로. 그 밖에는 빈 배열.
        var strings: [String] {
            switch self {
            case .scalar(let value): return [value]
            case .list(let items): return items.flatMap { $0.strings }
            case .map: return []
            }
        }

        /// 스칼라 여러 개를 담은 목록. 목록이 아니면 빈 배열.
        var maps: [[String: Value]] {
            guard case .list(let items) = self else { return [] }
            return items.compactMap { item in
                if case .map(let entries) = item { return entries }
                return nil
            }
        }
    }

    static func parse(_ text: String) -> Value? {
        let lines = makeLines(text)
        guard !lines.isEmpty else { return nil }
        var index = 0
        return parseBlock(lines, &index, indent: lines[0].indent)
    }

    // MARK: - 줄 다듬기

    private struct Line {
        let indent: Int
        let text: String
    }

    private static func makeLines(_ text: String) -> [Line] {
        // Swift에서 "\r\n"은 한 글자라 "\n"으로 나눌 수 없다. 먼저 줄바꿈을 통일한다.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [Line] = []
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var raw = String(rawLine)
            if raw.hasPrefix("\u{FEFF}") { raw.removeFirst() }   // BOM

            let withoutComment = stripComment(raw)
            let indent = withoutComment.prefix { $0 == " " }.count
            let content = withoutComment.dropFirst(indent).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            lines.append(Line(indent: indent, text: content))
        }
        return lines
    }

    /// 따옴표 밖의 `#` 뒤를 잘라낸다. `#` 앞에 공백이 있어야 주석으로 본다.
    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "'", !inDouble {
                inSingle.toggle()
            } else if character == "\"", !inSingle {
                inDouble.toggle()
            } else if character == "#", !inSingle, !inDouble {
                if index == line.startIndex { return "" }
                let previous = line[line.index(before: index)]
                if previous == " " || previous == "\t" { return String(line[..<index]) }
            }
            index = line.index(after: index)
        }
        return line
    }

    // MARK: - 본문

    private static func parseBlock(_ lines: [Line], _ index: inout Int, indent: Int) -> Value? {
        guard index < lines.count else { return nil }
        return lines[index].text.hasPrefix("-")
            ? parseSequence(lines, &index, indent: indent)
            : parseMap(lines, &index, indent: indent)
    }

    private static func parseMap(_ lines: [Line], _ index: inout Int, indent: Int) -> Value? {
        var entries: [String: Value] = [:]

        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, !line.text.hasPrefix("-") else { break }
            guard let (key, inline) = splitKey(line.text) else { break }
            index += 1

            if let inline {
                entries[key] = parseInlineValue(inline)
                continue
            }

            // 값이 다음 줄에 있다. 들여쓰기가 깊으면 블록, 같은 들여쓰기에서 '-'로 시작하면 목록이다.
            if index < lines.count, lines[index].indent > indent {
                entries[key] = parseBlock(lines, &index, indent: lines[index].indent)
            } else if index < lines.count, lines[index].indent == indent, lines[index].text.hasPrefix("-") {
                entries[key] = parseSequence(lines, &index, indent: indent)
            } else {
                entries[key] = .scalar("")
            }
        }

        return .map(entries)
    }

    private static func parseSequence(_ lines: [Line], _ index: inout Int, indent: Int) -> Value? {
        var items: [Value] = []

        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent, line.text.hasPrefix("-") else { break }

            let rest = String(line.text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1

            if rest.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    items.append(parseBlock(lines, &index, indent: lines[index].indent) ?? .scalar(""))
                } else {
                    items.append(.scalar(""))
                }
                continue
            }

            guard splitKey(rest) != nil else {
                items.append(parseInlineValue(rest))
                continue
            }

            // 항목이 map이다. '-' 뒤 첫 줄을 시작으로, 더 깊은 줄들을 이어 붙여 map으로 읽는다.
            let contentColumn = indent + (line.text.count - rest.count)
            var itemLines = [Line(indent: contentColumn, text: rest)]
            while index < lines.count, lines[index].indent > indent {
                itemLines.append(lines[index])
                index += 1
            }
            var itemIndex = 0
            items.append(parseMap(itemLines, &itemIndex, indent: contentColumn) ?? .map([:]))
        }

        return .list(items)
    }

    // MARK: - 값

    /// `key: value` 또는 `key:` 를 나눈다. 콜론이 없으면 nil.
    private static func splitKey(_ text: String) -> (key: String, value: String?)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let key = String(text[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(" ") else { return nil }

        let remainder = String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (unquote(key), remainder.isEmpty ? nil : remainder)
    }

    private static func parseInlineValue(_ text: String) -> Value {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return .scalar(unquote(trimmed))
        }
        let inner = trimmed.dropFirst().dropLast()
        let items = inner.split(separator: ",").map {
            Value.scalar(unquote($0.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .list(items)
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2 else { return text }
        if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            return String(text.dropFirst().dropLast())
        }
        return text
    }
}
