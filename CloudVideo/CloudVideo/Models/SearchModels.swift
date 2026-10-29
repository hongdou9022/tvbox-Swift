import Foundation

// MARK: - 本地源配置（`/api/app/v1/local-sources`）

/// 影视站（`sites[]`，仅 `type=2` 的 T1 JSON 采集站）。
struct LocalSite: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let api: String?
    let type: Int?
    let priority: Int?
    let isHomeSearch: Bool?
    let tags: [String]?

    var homeSearch: Bool { isHomeSearch ?? false }
    var weight: Int { priority ?? 0 }
}

/// 爬虫源（`spiders[]`）。
struct LocalSpider: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let language: String?
    let scriptUrl: String?
    let scriptMd5: String?
    let priority: Int?
    let isHomeSearch: Bool?
    let clientCompatible: Bool?

    var homeSearch: Bool { isHomeSearch ?? false }
    var compatible: Bool { clientCompatible ?? false }
    var weight: Int { priority ?? 0 }
}

struct LocalSources: Codable {
    let version: String?
    let concurrency: Int?
    let sites: [LocalSite]?
    let spiders: [LocalSpider]?
}

// MARK: - 站点直连搜索结果（`/api/site-media/{id}/search`）

/// 后端 `adapters.SiteVod`，字段为 T1 JSON 原始命名。
struct SiteVod: Decodable, Hashable {
    let vodId: String?
    let vodName: String?
    let vodPic: String?
    let typeName: String?
    let vodRemarks: String?
    let vodYear: String?
    let vodArea: String?
    let vodDoubanScore: String?

    enum CodingKeys: String, CodingKey {
        case vodId = "vod_id"
        case vodName = "vod_name"
        case vodPic = "vod_pic"
        case typeName = "type_name"
        case vodRemarks = "vod_remarks"
        case vodYear = "vod_year"
        case vodArea = "vod_area"
        case vodDoubanScore = "vod_douban_score"
    }
}

struct SiteSearchPage: Decodable {
    let page: Int?
    let pagecount: Int?
    let total: Int?
    let list: [SiteVod]?

    enum CodingKeys: String, CodingKey {
        case page
        case pagecount
        case total
        case list
    }
}

// MARK: - 搜索范围

/// 规范 4.1 / SEARCH_OPTIMIZATION 2.2：`""` 全站、`site`、`spider` 三种。
enum SearchScope: Hashable {
    case all
    case site(id: String, name: String)
    case spider(id: String, name: String)

    var title: String {
        switch self {
        case .all: return "全站"
        case .site(_, let name): return name
        case .spider(_, let name): return name
        }
    }

    /// 持久化用的三元组。
    var stored: [String]? {
        switch self {
        case .all: return nil
        case .site(let id, let name): return ["site", id, name]
        case .spider(let id, let name): return ["spider", id, name]
        }
    }

    static func restore(_ values: [String]?) -> SearchScope? {
        guard let values, values.count == 3 else { return nil }
        switch values[0] {
        case "site": return .site(id: values[1], name: values[2])
        case "spider": return .spider(id: values[1], name: values[2])
        default: return nil
        }
    }
}

// MARK: - 搜索目标（逐源并发的最小单位）

/// 一个可搜索的源。站点走 `/api/site-media/{id}/search`，爬虫走 `/api/app/v1/search?sourceId=`。
struct SearchTarget: Identifiable, Hashable {
    enum Kind: String {
        case site
        case spider
    }

    let id: String
    let name: String
    let kind: Kind
    let priority: Int

    /// 范围菜单里的角标：站类标 `· 站`，爬虫标 `· 源`（规范 4.1）。
    var suffix: String {
        kind == .site ? "· 站" : "· 源"
    }
}

// MARK: - 结果条目（带排序中间量）

/// 池内条目：`MediaItem` + 排序所需的中间量。
///
/// 规范 4.4.5 的同分比较需要 `matchRank`、源优先级与来源名；
/// SEARCH_OPTIMIZATION 4.2 的 `tokenHit` 记录命中的词序，用于同 rank 内再分先后。
struct SearchHit: Identifiable, Hashable {
    let item: MediaItem
    let matchRank: Int
    /// 命中的分词下标，越小说明命中的词越靠前；未命中为 `Int.max`。
    let tokenHit: Int
    /// 是否来自 2 分钟缓存（SEARCH_OPTIMIZATION 4.3 的角标预留）。
    let fromCache: Bool

    var id: String { item.id }
}

/// 一次搜索的统计（规范 4.3 / 第 8 章文案）。
struct SearchStats {
    var returnedSources = 0
    var queriedSources = 0
    var failedSources = 0
    var timedOut = false
    var totalHits = 0
}
