import SwiftUI
import Combine

/// 搜索页状态（`PHONE_UI_SPEC.md` 第 4 章 v1.14 + `SEARCH_OPTIMIZATION.md`）。
@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - 输入与范围

    @Published var keyword = ""
    @Published private(set) var scope: SearchScope = .all
    /// 范围菜单项（第一项是全站，其余是勾选「首页搜索」的源）。
    @Published private(set) var menuTargets: [SearchTarget] = []
    /// 结果页左侧源栏的当前选中项，`nil` 表示「全部」。
    @Published private(set) var selectedSourceId: String?

    // MARK: - 空态

    @Published private(set) var history: [String] = []
    @Published private(set) var hotWords: [String] = []

    let coordinator = SearchCoordinator()

    private let api = APIClient.shared
    private let historyKey = "cloudvideo.search.history"
    private static let scopeKey = "cloudvideo.search.scope"
    private var didPrepare = false
    private var bag = Set<AnyCancellable>()

    init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        scope = SearchScope.restore(UserDefaults.standard.stringArray(forKey: Self.scopeKey)) ?? .all

        // 把协调器的变化转发给视图，避免外面再持有一份 ObservableObject
        coordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &bag)
    }

    // MARK: - 派生状态

    var isSearching: Bool { coordinator.isSearching }

    /// 当前展示的条目：选中具体源时按 `libraryId` 过滤（规范 4.3）。
    var hits: [SearchHit] {
        guard let selectedSourceId else { return coordinator.hits }
        return coordinator.hits.filter { $0.item.libraryId == selectedSourceId }
    }

    /// 左侧源栏：第一项固定「全部」，其后是本次实际返回过结果的源。
    var sourceRail: [SearchSourceEntry] {
        var entries = [SearchSourceEntry(id: nil, name: "全部", count: coordinator.hits.count)]
        for id in coordinator.returnedSourceIds {
            let count = coordinator.hits.filter { $0.item.libraryId == id }.count
            entries.append(SearchSourceEntry(id: id, name: name(for: id), count: count))
        }
        return entries
    }

    /// 规范 4.3：只有 1 个来源时不显示该栏，列表占满宽度。
    var showsSourceRail: Bool {
        coordinator.returnedSourceIds.count > 1
    }

    /// 规范 4.1（v1.14）：统计行常驻，格式 `基准统计｜附加提示`，
    /// 两者都为空时兜底 `共 N 条结果`，绝不允许空文案。
    var statusLine: String {
        let parts = [coordinator.baseStatus, coordinator.extraStatus]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        if !parts.isEmpty {
            return parts.joined(separator: "｜")
        }
        return "共 \(coordinator.hits.count) 条结果"
    }

    var hasSearched: Bool {
        coordinator.baseStatus != nil || !coordinator.hits.isEmpty
    }

    /// 规范 4.1：无可选源时提示。
    var menuEmptyHint: String? {
        menuTargets.isEmpty ? "暂无可选来源，请先在服务端勾选首页搜索" : nil
    }

    // MARK: - 准备

    /// 搜索页每次打开**强制刷新**源配置（跳过 10 分钟缓存）。
    func prepareIfNeeded(force: Bool = true) async {
        if force || !didPrepare {
            await LocalSourceStore.shared.load(force: force)
            menuTargets = LocalSourceStore.shared.menuTargets()
            didPrepare = true
        }

        // 持久化的范围如果已不在菜单里（后台取消了勾选），回退到全站
        if case .site(let id, _) = scope, !menuTargets.contains(where: { $0.id == id }) {
            scope = .all
            persistScope(.all)
        }
        if case .spider(let id, _) = scope, !menuTargets.contains(where: { $0.id == id }) {
            scope = .all
            persistScope(.all)
        }

        await loadHotWords()
    }

    /// 规范 4.2：热搜内容为**首页热播标题**，最多 6 条；不属于用户数据，不提供删除。
    private func loadHotWords() async {
        guard hotWords.isEmpty else { return }

        var words: [String] = []
        let recommend = try? await api.recommend()
        let titles = (recommend?.sections ?? []).flatMap { $0.items }.map { $0.title }
        for title in titles where words.count < 6 {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !words.contains(trimmed) {
                words.append(trimmed)
            }
        }
        hotWords = words
    }

    // MARK: - 搜索

    func search() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        remember(trimmed)
        selectedSourceId = nil
        coordinator.search(keyword: trimmed, scope: scope)
    }

    func useKeyword(_ text: String) {
        keyword = text
        search()
    }

    /// 规范 4.1：选择范围后写入本地配置，并立即用当前关键词重搜。
    func applyScope(_ newScope: SearchScope) {
        guard newScope != scope else { return }
        scope = newScope
        persistScope(newScope)
        selectedSourceId = nil

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coordinator.search(keyword: trimmed, scope: newScope)
    }

    /// 规范 4.3：切换来源只过滤已取到的结果，**不重新发起网络请求**。
    func selectSource(_ id: String?) {
        selectedSourceId = id

        if let id {
            let count = coordinator.hits.filter { $0.item.libraryId == id }.count
            coordinator.setExtraStatus(count == 0 ? "该来源没有结果" : nil)
        } else {
            coordinator.setExtraStatus(nil)
        }
    }

    /// 规范 v1.9：清空按钮同步重置源栏。
    func clear() {
        keyword = ""
        selectedSourceId = nil
        coordinator.reset()
    }

    func cancel() {
        coordinator.cancel()
    }

    // MARK: - 工具

    func name(for sourceId: String) -> String {
        if let matched = menuTargets.first(where: { $0.id == sourceId }) {
            return matched.name
        }
        if let hit = coordinator.hits.first(where: { $0.item.libraryId == sourceId }) {
            return hit.item.libraryName
        }
        return sourceId
    }

    private func persistScope(_ scope: SearchScope) {
        if let stored = scope.stored {
            UserDefaults.standard.set(stored, forKey: Self.scopeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.scopeKey)
        }
    }

    // MARK: - 历史（规范 4.2）

    private func remember(_ text: String) {
        // 重复搜索不新增条目，只把该词移到第 1 位
        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func removeHistory(_ text: String) {
        history.removeAll { $0 == text }
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.set(history, forKey: historyKey)
    }
}

/// 左侧源栏的一项。`id` 为 `nil` 表示「全部」。
struct SearchSourceEntry: Hashable {
    let id: String?
    let name: String
    let count: Int

    var key: String { id ?? "__all__" }
}
