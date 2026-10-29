import Foundation

/// 搜索结果排序，严格对齐 `PHONE_UI_SPEC.md` 4.4 与 `SEARCH_OPTIMIZATION.md` 4.2。
///
/// 总顺序：匹配度 → 词序命中 → 源优先级 → 来源名 → 片名。
///
/// 说明：`PHONE_UI_SPEC` 4.4.5 的完整比较函数里没有词序命中，但
/// `SEARCH_OPTIMIZATION` v1.4 补了 `tokenHit`（「同 rank 内先比它」），
/// 两份文档冲突处以更新的 SEARCH_OPTIMIZATION 为准，其余三级完全一致。
enum SearchRanker {

    // MARK: - 4.4.2 归一化

    /// 规范里明确列出的、需要剔除的分隔符与括号。
    /// 注意：只去掉括号本身，括号里的内容保留。
    private static let normalizeSeparators: Set<Character> = [
        "·", ":", "：", ",", "，", ".", "。", "!", "！", "?", "？",
        "-", "—", "_", "/", "|",
        "(", ")", "（", "）", "[", "]", "【", "】"
    ]

    /// 4.4.3 分词用的分隔符。规范里这一组**不含括号**。
    private static let tokenSeparators: Set<Character> = [
        "·", ":", "：", ",", "，", ".", "。", "!", "！", "?", "？",
        "-", "—", "_", "/", "|"
    ]

    static func normalize(_ text: String?) -> String {
        guard let text else { return "" }
        let lowered = text.lowercased()
        return String(lowered.filter { char in
            !char.isWhitespace && !normalizeSeparators.contains(char)
        })
    }

    /// 按空白与标点拆分**原始**关键词。
    private static func tokens(of keyword: String) -> [String] {
        keyword
            .split(whereSeparator: { char in
                char.isWhitespace || tokenSeparators.contains(char)
            })
            .map(String.init)
    }

    // MARK: - 4.4.3 匹配度

    /// rank 越小越靠前；4 表示不相关，但**不丢弃**，只排到最后。
    static func matchRank(keyword: String, title: String) -> Int {
        let q = normalize(keyword)
        let n = normalize(title)
        guard !q.isEmpty, !n.isEmpty else { return 4 }

        if n == q { return 0 }
        if n.hasPrefix(q) { return 1 }
        if n.contains(q) { return 2 }

        // 分词用的是原始关键词拆分，每个词再各自归一化后比较，
        // 所以「凡人 修仙传」能命中「凡人修仙传」。
        for token in tokens(of: keyword) {
            let normalized = normalize(token)
            // 单字词不参与，避免「的」「之」造成大量误命中
            if normalized.count >= 2, n.contains(normalized) {
                return 3
            }
        }

        return 4
    }

    /// 词序命中：命中的分词下标，越小说明命中的词越靠前；未命中为 `Int.max`。
    ///
    /// SEARCH_OPTIMIZATION 4.2：修复「斗破苍穹 年番」与「凡人修仙传」并列的问题。
    static func tokenHit(keyword: String, title: String) -> Int {
        let n = normalize(title)
        guard !n.isEmpty else { return Int.max }

        for (index, token) in tokens(of: keyword).enumerated() {
            let normalized = normalize(token)
            if normalized.count >= 2, n.contains(normalized) {
                return index
            }
        }
        return Int.max
    }

    // MARK: - 4.4.6 粗过滤

    /// 比 rank 宽松：`q.contains(n)` 也算命中（搜「凡人修仙传 年番」能返回「凡人修仙传」）。
    static func matchesKeyword(keyword: String, title: String) -> Bool {
        let q = normalize(keyword)
        let n = normalize(title)

        // 太短无法判定，放行
        if q.count < 2 || n.count < 2 { return true }

        if n.contains(q) || q.contains(n) { return true }

        for token in tokens(of: keyword) {
            let normalized = normalize(token)
            if normalized.count >= 2, n.contains(normalized) {
                return true
            }
        }
        return false
    }

    // MARK: - 4.4.5 排序

    /// - Parameter priority: `sourceId -> 权重`，规范 4.4.4：`totalCount - index`，越大越靠前。
    /// - Returns: 已算好 `matchRank` / `tokenHit` 的条目，按 4.4.5 排好序。
    static func rank(
        _ items: [MediaItem],
        keyword: String,
        priority: [String: Int]
    ) -> [SearchHit] {
        var seen = Set<String>()
        var hits: [SearchHit] = []

        for item in items {
            guard !item.title.isEmpty else { continue }
            guard matchesKeyword(keyword: keyword, title: item.title) else { continue }
            // 去重键 = libraryId + "|" + videoId（规范 4.4.6）
            guard seen.insert(item.id).inserted else { continue }

            hits.append(
                SearchHit(
                    item: item,
                    matchRank: matchRank(keyword: keyword, title: item.title),
                    tokenHit: tokenHit(keyword: keyword, title: item.title),
                    fromCache: false
                )
            )
        }

        return sort(hits, priority: priority)
    }

    /// 整池重排（规范 4.4.7：不做局部插入，每批到达后整体排序一次）。
    static func sort(_ hits: [SearchHit], priority: [String: Int]) -> [SearchHit] {
        hits.sorted { lhs, rhs in
            // 1) 匹配度升序
            if lhs.matchRank != rhs.matchRank { return lhs.matchRank < rhs.matchRank }

            // 2) 词序命中升序（命中的词越靠前越好）
            if lhs.tokenHit != rhs.tokenHit { return lhs.tokenHit < rhs.tokenHit }

            // 3) 源优先级降序
            let lp = priority[lhs.item.libraryId] ?? 0
            let rp = priority[rhs.item.libraryId] ?? 0
            if lp != rp { return lp > rp }

            // 4) 来源名升序
            if lhs.item.libraryName != rhs.item.libraryName {
                return lhs.item.libraryName < rhs.item.libraryName
            }

            // 5) 片名升序（最终稳定键）
            return lhs.item.title < rhs.item.title
        }
    }
}
