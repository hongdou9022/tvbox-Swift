import Foundation

/// 本地源配置（`/api/app/v1/local-sources`）。
///
/// 规范 4.1 / SEARCH_OPTIMIZATION 2.2：
/// - 配置缓存 10 分钟，带 ETag 条件请求，未变返回 304；
/// - 搜索页每次打开强制刷新，保证后台改的勾选立刻可见；
/// - 全站搜索**不受** `isHomeSearch` 限制，该开关只影响首页推荐与范围菜单。
@MainActor
final class LocalSourceStore {

    static let shared = LocalSourceStore()

    /// 配置缓存有效期（SEARCH_OPTIMIZATION 2.5）。
    static let cacheTTL: TimeInterval = 10 * 60

    private let defaults = UserDefaults.standard
    private let payloadKey = "cloudvideo.sources.payload"
    private let etagKey = "cloudvideo.sources.etag"
    private let timeKey = "cloudvideo.sources.time"

    private(set) var sources: LocalSources?
    private(set) var etag: String?
    private var fetchedAt: Date?

    /// 并发上限：服务端下发 1–8，默认 8（SEARCH_OPTIMIZATION 2.4）。
    var concurrency: Int {
        let value = sources?.concurrency ?? 8
        return min(max(value, 1), 8)
    }

    var sites: [LocalSite] { sources?.sites ?? [] }
    var spiders: [LocalSpider] { sources?.spiders ?? [] }

    /// 配置版本，参与搜索缓存 key，配置一变缓存自动失效。
    var version: String { sources?.version ?? "0" }

    private init() {
        loadFromDisk()
    }

    // MARK: - 拉取

    /// - Parameter force: 跳过 10 分钟缓存（搜索页每次打开都传 true）。
    func load(force: Bool) async {
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.cacheTTL, sources != nil {
            return
        }

        do {
            let result = try await APIClient.shared.localSources(etag: force ? nil : etag)
            switch result {
            case .notModified:
                fetchedAt = Date()
                defaults.set(Date().timeIntervalSince1970, forKey: timeKey)
            case .fresh(let payload, let newEtag):
                sources = payload
                etag = newEtag
                fetchedAt = Date()
                persist(payload: payload, etag: newEtag)
            }
        } catch {
            // 拿不到就走缓存，缓存也没有就留空（搜索会退化成服务端聚合）
        }
    }

    // MARK: - 范围菜单（规范 4.1）

    /// 菜单项：第一项「全站」，其余为后端勾选「首页搜索」的源。
    ///
    /// 必须同时收两类源：`sites`（type=2）与 `spiders`（clientCompatible=true），
    /// 否则「荐片」这类只存在于 spiders 里的源会被漏掉。
    /// 排序：爬虫优先 → `priority` 降序 → 名称升序。
    func menuTargets() -> [SearchTarget] {
        var list: [SearchTarget] = []

        for site in sites where site.homeSearch {
            list.append(SearchTarget(id: site.id, name: site.name, kind: .site, priority: site.weight))
        }
        for spider in spiders where spider.homeSearch && spider.compatible {
            list.append(SearchTarget(id: spider.id, name: spider.name, kind: .spider, priority: spider.weight))
        }

        return list.sorted { lhs, rhs in
            if (lhs.kind == .spider) != (rhs.kind == .spider) {
                return lhs.kind == .spider
            }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.name < rhs.name
        }
    }

    // MARK: - 搜索目标（规范 4.1 + SEARCH_OPTIMIZATION 2.2）

    /// 全站：查**全部**已启用源，不受 `isHomeSearch` 限制。
    /// 单源：只查该源，即便它没勾选首页搜索。
    func targets(for scope: SearchScope) -> [SearchTarget] {
        switch scope {
        case .all:
            var list: [SearchTarget] = []
            for site in sites {
                list.append(SearchTarget(id: site.id, name: site.name, kind: .site, priority: site.weight))
            }
            for spider in spiders where spider.compatible {
                list.append(SearchTarget(id: spider.id, name: spider.name, kind: .spider, priority: spider.weight))
            }
            return list

        case .site(let id, let name):
            let matched = sites.first { $0.id == id }
            return [SearchTarget(id: id, name: matched?.name ?? name, kind: .site, priority: matched?.weight ?? 0)]

        case .spider(let id, let name):
            let matched = spiders.first { $0.id == id }
            return [SearchTarget(id: id, name: matched?.name ?? name, kind: .spider, priority: matched?.weight ?? 0)]
        }
    }

    /// 规范 4.4.4：`priority[sourceId] = totalCount - index`，越大越靠前。
    ///
    /// 按范围菜单的顺序（爬虫优先 → priority 降序 → 名称）编号，
    /// 这样同一批结果的源优先级与用户看到的菜单顺序一致。
    func priorityMap() -> [String: Int] {
        let ordered = menuTargets()
        let total = ordered.count
        var map: [String: Int] = [:]
        for (index, target) in ordered.enumerated() {
            map[target.id] = total - index
        }
        return map
    }

    // MARK: - 磁盘

    private func loadFromDisk() {
        if let data = defaults.data(forKey: payloadKey),
           let decoded = try? JSONDecoder().decode(LocalSources.self, from: data) {
            sources = decoded
        }
        etag = defaults.string(forKey: etagKey)

        let stamp = defaults.double(forKey: timeKey)
        if stamp > 0 {
            fetchedAt = Date(timeIntervalSince1970: stamp)
        }
    }

    private func persist(payload: LocalSources, etag: String?) {
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: payloadKey)
        }
        if let etag {
            defaults.set(etag, forKey: etagKey)
        } else {
            defaults.removeObject(forKey: etagKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: timeKey)
    }
}
