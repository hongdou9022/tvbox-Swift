import Foundation

/// 单源搜索结果。
struct TargetResult {
    let target: SearchTarget
    let items: [MediaItem]
    let latencyMs: Int
    let error: String?
    let timedOut: Bool
}

/// 逐源抓取。放在 `SearchCoordinator` 外面，避免并发任务里捕获 MainActor 状态。
enum SearchFetcher {

    static func fetch(_ target: SearchTarget, keyword: String, page: Int) async -> TargetResult {
        let started = Date()

        do {
            switch target.kind {
            case .site:
                let pageData = try await APIClient.shared.siteSearch(
                    siteId: target.id,
                    keyword: keyword,
                    page: page
                )
                let items = (pageData.list ?? []).compactMap { vod -> MediaItem? in
                    guard let id = vod.vodId, !id.isEmpty,
                          let name = vod.vodName, !name.isEmpty else { return nil }
                    return MediaItem(
                        sourceType: "site",
                        libraryId: target.id,
                        libraryName: target.name,
                        videoId: id,
                        title: name,
                        poster: vod.vodPic,
                        remark: vod.vodRemarks,
                        year: vod.vodYear,
                        score: vod.vodDoubanScore,
                        typeName: vod.typeName
                    )
                }
                return TargetResult(
                    target: target,
                    items: items,
                    latencyMs: elapsed(from: started),
                    error: nil,
                    timedOut: false
                )

            case .spider:
                // 爬虫源的搜索在服务端执行（接口规范 7.2 允许 iOS 先全走服务端）
                let pageData = try await APIClient.shared.search(
                    keyword: keyword,
                    page: page,
                    sourceId: target.id
                )
                return TargetResult(
                    target: target,
                    items: pageData.items,
                    latencyMs: elapsed(from: started),
                    error: nil,
                    timedOut: false
                )
            }
        } catch {
            let timedOut: Bool
            if case APIError.transport(let message) = error {
                timedOut = message.lowercased().contains("timed out")
                    || message.contains("超时")
            } else {
                timedOut = false
            }
            return TargetResult(
                target: target,
                items: [],
                latencyMs: elapsed(from: started),
                error: error.localizedDescription,
                timedOut: timedOut
            )
        }
    }

    private static func elapsed(from start: Date) -> Int {
        max(Int(Date().timeIntervalSince(start) * 1000), 1)
    }
}

/// 搜索编排（SEARCH_OPTIMIZATION 第 1、2 章）。
///
/// 双通道：
/// - 影视站 → `/api/site-media/{id}/search`，客户端逐源并发（滑动窗口调度）
/// - 爬虫源 → `/api/app/v1/search?sourceId=`，服务端执行
///
/// 结果进池后**整池重排**再整体刷新，不做局部插入（规范 4.4.7）。
@MainActor
final class SearchCoordinator: ObservableObject {

    /// 流式总预算。单源 3.5s 的预算由 `APIClient` 的短超时会话强制
    /// （`searchSession.timeoutIntervalForRequest`），见 SEARCH_OPTIMIZATION 2.4。
    static let streamBudget: TimeInterval = 20
    /// 失败源冷却（SEARCH_OPTIMIZATION 2.3）。
    static let cooldown: TimeInterval = 5 * 60

    @Published private(set) var hits: [SearchHit] = []
    /// 本次实际返回过结果的源，按首次出现顺序（规范 4.3）。
    @Published private(set) var returnedSourceIds: [String] = []
    @Published private(set) var isSearching = false
    /// 基准统计：整轮搜索期间不变（规范 4.1 v1.14）。
    @Published private(set) var baseStatus: String?
    /// 附加提示：临时文案，切换来源即刷新。
    @Published private(set) var extraStatus: String?

    private var pool: [MediaItem] = []
    private var seen = Set<String>()
    private var cooldowns: [String: Date] = [:]
    private var queriedCount = 0
    private var failedCount = 0
    private var timedOut = false
    private var generation = 0
    private var currentTask: Task<Void, Never>?
    private var currentKeyword = ""
    private var currentScope: SearchScope = .all

    // MARK: - 搜索

    func search(keyword: String, scope: SearchScope, page: Int = 1) {
        cancel()
        generation += 1
        let gen = generation

        pool = []
        seen = []
        returnedSourceIds = []
        hits = []
        queriedCount = 0
        failedCount = 0
        timedOut = false
        extraStatus = nil

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        currentKeyword = trimmed
        currentScope = scope

        guard !trimmed.isEmpty else {
            baseStatus = nil
            isSearching = false
            return
        }

        // 命中缓存直接出结果（SEARCH_OPTIMIZATION 2.5）
        let cacheKey = SearchCache.shared.key(keyword: trimmed, page: page, scope: scope)
        if let cached = SearchCache.shared.value(for: cacheKey) {
            hits = cached.hits
            returnedSourceIds = cached.sources
            queriedCount = cached.stats.queriedSources
            failedCount = cached.stats.failedSources
            timedOut = cached.stats.timedOut
            baseStatus = makeBaseStatus(keyword: trimmed, targetCount: cached.stats.queriedSources)
            isSearching = false
            return
        }

        let allTargets = LocalSourceStore.shared.targets(for: scope)
        let available = allTargets.filter { !isCooling($0.id) }
        let ordered = orderByScore(available)

        isSearching = true

        if ordered.isEmpty {
            // 配置不可用（未同步到源）→ 回落服务端聚合搜索
            currentTask = Task { [weak self] in
                await self?.searchViaServer(keyword: trimmed, scope: scope, generation: gen)
            }
            return
        }

        baseStatus = makeBaseStatus(keyword: trimmed, targetCount: ordered.count)

        currentTask = Task { [weak self] in
            await self?.runWindow(ordered, keyword: trimmed, page: page, generation: gen)
        }
    }

    /// 滑动窗口调度（SEARCH_OPTIMIZATION 4.1）：先提交 N 个，完成一个立即补一个。
    private func runWindow(
        _ targets: [SearchTarget],
        keyword: String,
        page: Int,
        generation gen: Int
    ) async {
        let window = max(LocalSourceStore.shared.concurrency, 1)
        let deadline = Date().addingTimeInterval(Self.streamBudget)

        await withTaskGroup(of: TargetResult.self) { group in
            var next = 0
            var inFlight = 0

            while inFlight < window, next < targets.count {
                let target = targets[next]
                next += 1
                inFlight += 1
                group.addTask { await SearchFetcher.fetch(target, keyword: keyword, page: page) }
            }

            while let result = await group.next() {
                inFlight -= 1

                if gen != generation {
                    group.cancelAll()
                    return
                }

                consume(result, keyword: keyword)
                publish()

                // 超出总预算就不再提交新源，已返回的照常展示
                if Date() < deadline, next < targets.count {
                    let target = targets[next]
                    next += 1
                    inFlight += 1
                    group.addTask { await SearchFetcher.fetch(target, keyword: keyword, page: page) }
                } else if Date() >= deadline {
                    timedOut = true
                }
            }
        }

        guard gen == generation else { return }
        isSearching = false
        baseStatus = makeBaseStatus(keyword: keyword, targetCount: queriedCount)
        persistCache(keyword: keyword, page: page, scope: currentScope)
    }

    /// 本地源配置不可用时的兜底：服务端聚合搜索。
    private func searchViaServer(keyword: String, scope: SearchScope, generation gen: Int) async {
        var sourceId: String?
        var siteId: String?
        switch scope {
        case .all:
            break
        case .spider(let id, _):
            sourceId = id
        case .site(let id, _):
            siteId = id
        }

        do {
            let pageData = try await APIClient.shared.search(
                keyword: keyword,
                page: 1,
                sourceId: sourceId,
                siteId: siteId,
                includeSites: scope == .all
            )
            guard gen == generation else { return }

            for item in pageData.items {
                if seen.insert(item.id).inserted {
                    pool.append(item)
                }
                if !returnedSourceIds.contains(item.libraryId) {
                    returnedSourceIds.append(item.libraryId)
                }
            }
            queriedCount = max(returnedSourceIds.count, 1)
        } catch {
            guard gen == generation else { return }
            failedCount = 1
        }

        isSearching = false
        publish()
        baseStatus = makeBaseStatus(keyword: keyword, targetCount: queriedCount)
        persistCache(keyword: keyword, page: 1, scope: scope)
    }

    // MARK: - 结果合并

    private func consume(_ result: TargetResult, keyword: String) {
        queriedCount += 1

        if result.error != nil {
            failedCount += 1
            cooldowns[result.target.id] = Date()
            SourceScorer.shared.recordFailure(id: result.target.id)
            if result.timedOut { timedOut = true }
            return
        }

        SourceScorer.shared.recordSuccess(
            id: result.target.id,
            latencyMs: result.latencyMs,
            resultCount: result.items.count
        )

        if !result.items.isEmpty, !returnedSourceIds.contains(result.target.id) {
            returnedSourceIds.append(result.target.id)
        }

        for item in result.items where seen.insert(item.id).inserted {
            pool.append(item)
        }
    }

    /// 整池重排后整体刷新（规范 4.4.6 / 4.4.7）。
    private func publish() {
        hits = SearchRanker.rank(
            pool,
            keyword: currentKeyword,
            priority: LocalSourceStore.shared.priorityMap()
        )
    }

    // MARK: - 状态

    /// 规范 8 + 4.3：基准统计文案。
    private func makeBaseStatus(keyword: String, targetCount: Int) -> String {
        if isSearching {
            if failedCount > 0 {
                return "搜索中…已返回 \(returnedSourceIds.count) 个来源，\(failedCount) 个源失败"
            }
            return "搜索中…已返回 \(returnedSourceIds.count) 个来源"
        }

        if hits.isEmpty {
            return "没有找到「\(keyword)」"
        }

        if timedOut {
            return "已返回 \(returnedSourceIds.count) 个来源（查询 \(queriedCount)/\(max(targetCount, queriedCount))，部分站点未返回）"
        }

        if failedCount > 0 {
            return "已返回 \(returnedSourceIds.count) 个来源（查询 \(queriedCount) 个站点，\(failedCount) 个源失败）"
        }

        return "已返回 \(returnedSourceIds.count) 个来源（查询 \(queriedCount) 个站点）"
    }

    /// 切源时的附加提示（规范 4.1 v1.14：只更新附加提示，不重建整行）。
    func setExtraStatus(_ text: String?) {
        extraStatus = text
    }

    // MARK: - 工具

    private func isCooling(_ id: String) -> Bool {
        guard let since = cooldowns[id] else { return false }
        if Date().timeIntervalSince(since) < Self.cooldown { return true }
        cooldowns.removeValue(forKey: id)
        return false
    }

    /// SEARCH_OPTIMIZATION 2.3：动态评分降序 → 爬虫优先 → priority 降序 → 名称。
    private func orderByScore(_ targets: [SearchTarget]) -> [SearchTarget] {
        targets.sorted { lhs, rhs in
            let ls = SourceScorer.shared.score(for: lhs.id)
            let rs = SourceScorer.shared.score(for: rhs.id)
            if abs(ls - rs) > 0.01 { return ls > rs }
            if (lhs.kind == .spider) != (rhs.kind == .spider) { return lhs.kind == .spider }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.name < rhs.name
        }
    }

    private func persistCache(keyword: String, page: Int, scope: SearchScope) {
        guard !hits.isEmpty else { return }
        var stats = SearchStats()
        stats.returnedSources = returnedSourceIds.count
        stats.queriedSources = queriedCount
        stats.failedSources = failedCount
        stats.timedOut = timedOut
        stats.totalHits = hits.count

        SearchCache.shared.store(
            key: SearchCache.shared.key(keyword: keyword, page: page, scope: scope),
            hits: hits,
            stats: stats,
            sources: returnedSourceIds
        )
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func reset() {
        cancel()
        generation += 1
        pool = []
        seen = []
        hits = []
        returnedSourceIds = []
        baseStatus = nil
        extraStatus = nil
        isSearching = false
        queriedCount = 0
        failedCount = 0
        timedOut = false
    }
}
