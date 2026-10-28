import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword = ""
    @Published private(set) var results: [Video] = []
    @Published private(set) var isSearching = false
    @Published var message: String?
    @Published private(set) var history: [String] = []

    private let historyKey = "cloudvideo.search.history"
    private var searchTask: Task<Void, Never>?

    init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func search(app: AppState) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sources = app.searchableSources
        guard !sources.isEmpty else {
            message = "当前配置里没有可搜索的源"
            return
        }

        searchTask?.cancel()
        isSearching = true
        message = nil
        results = []

        remember(trimmed)

        let found = await VodService.shared.searchAll(sources: sources, keyword: trimmed)
        guard !Task.isCancelled else { return }

        // 同名同源的重复结果去掉
        var seen = Set<String>()
        var unique: [Video] = []
        for video in found {
            let key = video.sourceKey + "|" + video.id
            if seen.insert(key).inserted {
                unique.append(video)
            }
        }

        results = unique
        isSearching = false

        if unique.isEmpty {
            message = "没有找到「\(trimmed)」相关的内容"
        }
    }

    func useKeyword(_ text: String, app: AppState) {
        keyword = text
        Task { await search(app: app) }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        message = nil
        isSearching = false
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    private func remember(_ text: String) {
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        if history.count > 12 {
            history = Array(history.prefix(12))
        }
        UserDefaults.standard.set(history, forKey: historyKey)
    }
}
