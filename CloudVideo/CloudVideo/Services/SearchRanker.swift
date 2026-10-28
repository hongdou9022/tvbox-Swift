import Foundation

/// 搜索结果排序（规范 4.4）。
///
/// 后端已经做过一次排序，但规范要求客户端在结果到达后统一重排，
/// 避免「谁先回来谁在前」把完全匹配挤到后面。
enum SearchRanker {

    /// 匹配度分级，数值越小越靠前。
    private enum MatchLevel: Int {
        case exact = 0
        case prefix = 1
        case contains = 2
        case token = 3
        case other = 4
    }

    static func rank(_ items: [MediaItem], keyword: String, priority: [String: Int]) -> [MediaItem] {
        let normalizedKeyword = normalize(keyword)
        let tokens = keyword
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        let scored = items.enumerated().map { index, item -> (MediaItem, MatchLevel, Int, Int) in
            let title = normalize(item.title)
            let level = matchLevel(title: title, keyword: normalizedKeyword, tokens: tokens)
            let sourcePriority = priority[item.libraryId] ?? Int.max
            return (item, level, sourcePriority, index)
        }

        return scored.sorted { lhs, rhs in
            if lhs.1.rawValue != rhs.1.rawValue { return lhs.1.rawValue < rhs.1.rawValue }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            return lhs.3 < rhs.3
        }.map { $0.0 }
    }

    private static func matchLevel(title: String, keyword: String, tokens: [String]) -> MatchLevel {
        guard !keyword.isEmpty else { return .other }

        if title == keyword { return .exact }
        if title.hasPrefix(keyword) { return .prefix }
        if title.contains(keyword) { return .contains }
        if !tokens.isEmpty, tokens.contains(where: { title.contains($0) }) { return .token }
        return .other
    }

    /// 去标点、去空格、全角转半角后统一小写。
    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        )
        let scalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }
}
