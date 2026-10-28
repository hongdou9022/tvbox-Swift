import SwiftUI
import Combine

/// 搜索页状态（规范第 4 章）。
@MainActor
final class SearchViewModel: ObservableObject {

    /// 搜索范围（规范 4.1）。
    enum Scope: Hashable {
        case all
        case source(id: String, name: String)

        var title: String {
            switch self {
            case .all: return "全站"
            case .source(_, let name): return name
            }
        }
    }

    @Published var keyword = ""
    @Published var scope: Scope = .all
    @Published private(set) var sources: [SearchSource] = []
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var statusText: String?
    @Published private(set) var history: [String] = []
    @Published private(set) var hotWords: [String] = []

    private let api = APIClient.shared
    private let historyKey = "cloudvideo.search.history"
    private static let scopeKey = "cloudvideo.search.scope"
    private var didPrepare = false

    init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        restoreScope()
    }

    // MARK: - 准备

    func prepareIfNeeded() async {
        guard !didPrepare else { return }
        didPrepare = true

        let list = try? await api.searchSources()
        if let list {
            sources = list
        }
        await loadHotWords()
    }

    /// 规范 4.2：热搜词取自本地搜索历史 + 首页热播标题，最多 6 条。
    private func loadHotWords() async {
        var words: [String] = []

        for word in history where words.count < 6 {
            if !words.contains(word) { words.append(word) }
        }

        if words.count < 6 {
            let recommend = try? await api.recommend()
            let titles = (recommend?.sections ?? []).flatMap { $0.items }.map { $0.title }
            for title in titles where words.count < 6 {
                if !title.isEmpty, !words.contains(title) {
                    words.append(title)
                }
            }
        }

        hotWords = words
    }

    // MARK: - 搜索

    func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        remember(trimmed)
        isSearching = true
        results = []
        statusText = "搜索中…"

        let sourceId: String?
        switch scope {
        case .all: sourceId = nil
        case .source(let id, _): sourceId = id
        }

        do {
            let page = try await api.search(keyword: trimmed, page: 1, sourceId: sourceId)

            // 规范 4.4.4：越靠前优先级越高，取值 totalCount - index，排序时降序
            let total = sources.count
            let priority = Dictionary(
                uniqueKeysWithValues: sources.enumerated().map { ($1.id, total - $0) }
            )
            results = SearchRanker.rank(page.items, keyword: trimmed, priority: priority)

            let returnedSources = Set(results.map { $0.libraryId }).count
            if results.isEmpty {
                statusText = "没有找到「\(trimmed)」"
            } else {
                // 规范 8：已返回 N 个来源（查询 X 个站点）
                let queried = sourceId == nil ? sources.count : 1
                statusText = "已返回 \(returnedSources) 个来源（查询 \(queried) 个站点）"
            }
        } catch {
            statusText = error.localizedDescription
        }

        isSearching = false
    }

    /// 规范 4.1：选择范围后写入本地配置，并立即用当前关键词重搜。
    func applyScope(_ newScope: Scope) async {
        guard newScope != scope else { return }
        scope = newScope
        persistScope(newScope)

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await search()
    }

    private func persistScope(_ scope: Scope) {
        switch scope {
        case .all:
            UserDefaults.standard.removeObject(forKey: Self.scopeKey)
        case .source(let id, let name):
            UserDefaults.standard.set([id, name], forKey: Self.scopeKey)
        }
    }

    private func restoreScope() {
        guard let saved = UserDefaults.standard.stringArray(forKey: Self.scopeKey),
              saved.count == 2 else { return }
        scope = .source(id: saved[0], name: saved[1])
    }

    func useKeyword(_ text: String) async {
        keyword = text
        await search()
    }

    func clear() {
        keyword = ""
        results = []
        statusText = nil
    }

    // MARK: - 历史

    private func remember(_ text: String) {
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        if history.count > 12 {
            history = Array(history.prefix(12))
        }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.set(history, forKey: historyKey)
    }
}
