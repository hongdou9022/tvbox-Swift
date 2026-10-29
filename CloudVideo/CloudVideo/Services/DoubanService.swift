import Foundation

/// 豆瓣直连（`PHONE_UI_SPEC.md` 3.5 / 3.3 + `PHONE_FUNCTION_API_SPEC.md` 6.1）。
///
/// 客户端直连豆瓣**优先**，后端 `/api/app/v1/recommend` 与 `/api/douban-recommendation` 兜底。
/// 接口需要 `User-Agent` 与 `Referer: https://m.douban.com`，否则返回异常（规范 9.7）。
///
/// 豆瓣条目只有豆瓣 id，**没有可播放地址**；卡片点击按剧名跳搜索页（规范 3.4）。
enum DoubanService {

    /// 豆瓣条目的伪源标识。`MediaTarget` 见到它会把 libraryId 置空，
    /// 从而走「按剧名跳搜索」而不是去调 `media` 接口。
    static let sourceId = "douban"
    static let sourceName = "豆瓣"

    /// 豆瓣把综艺也标成 `type=tv`，所以类型一律由**请求分区**回填（规范 3.5）。
    enum Channel {
        case tv
        case movie
        case anime
        case variety

        /// 卡片角标文字（规范 3.4：剧集 / 电影 / 动漫 / 综艺）。
        var badge: String {
            switch self {
            case .tv: return "剧集"
            case .movie: return "电影"
            case .anime: return "动漫"
            case .variety: return "综艺"
            }
        }

        var title: String {
            switch self {
            case .tv: return "电视剧推荐"
            case .movie: return "电影推荐"
            case .anime: return "动漫推荐"
            case .variety: return "综艺推荐"
            }
        }

        /// 分区 `type` 字段，客户端频道切换用。
        var type: String {
            switch self {
            case .tv: return "tv"
            case .movie: return "movie"
            case .anime: return "anime"
            case .variety: return "variety"
            }
        }
    }

    /// 每页 18 条（规范 3.5）。
    static let pageSize = 18

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://m.douban.com",
            "Accept": "application/json"
        ]
        return URLSession(configuration: config)
    }()

    // MARK: - 抓取

    /// 拉某个频道的第 `page` 页（从 1 开始）。
    static func fetch(_ channel: Channel, page: Int) async -> [MediaItem] {
        let start = max(page - 1, 0) * pageSize

        switch channel {
        case .tv:
            return await fetchRecentHot(path: "tv", category: "tv", type: "tv", start: start, channel: channel)
        case .movie:
            return await fetchRecentHot(path: "movie", category: "热门", type: "全部", start: start, channel: channel)
        case .variety:
            return await fetchRecentHot(path: "tv", category: "综艺", type: "综艺", start: start, channel: channel)
        case .anime:
            // 豆瓣 recent_hot 没有动漫分类，必须走搜索接口
            return await fetchSearch(tags: "动漫", start: start, channel: channel)
        }
    }

    private static func fetchRecentHot(
        path: String,
        category: String,
        type: String,
        start: Int,
        channel: Channel
    ) async -> [MediaItem] {
        guard var components = URLComponents(
            string: "https://m.douban.com/rexxar/api/v2/subject/recent_hot/\(path)"
        ) else { return [] }

        components.queryItems = [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "limit", value: "\(pageSize)")
        ]
        guard let url = components.url else { return [] }

        guard let page: DoubanRawPage = await get(url) else { return [] }
        return map(page.items ?? [], channel: channel)
    }

    private static func fetchSearch(tags: String, start: Int, channel: Channel) async -> [MediaItem] {
        guard var components = URLComponents(string: "https://movie.douban.com/j/new_search_subjects")
        else { return [] }

        components.queryItems = [
            URLQueryItem(name: "sort", value: "U"),
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "range", value: "0,10")
        ]
        guard let url = components.url else { return [] }

        guard let page: DoubanRawPage = await get(url) else { return [] }
        return map(page.data ?? [], channel: channel)
    }

    private static func get<T: Decodable>(_ url: URL) async -> T? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - 映射

    private static func map(_ items: [DoubanRawItem], channel: Channel) -> [MediaItem] {
        items.compactMap { raw in
            guard let id = raw.id, !id.isEmpty,
                  let title = raw.title, !title.isEmpty else { return nil }

            let poster = raw.posterURL

            return MediaItem(
                sourceType: nil,
                libraryId: sourceId,
                libraryName: sourceName,
                videoId: id,
                title: title,
                poster: poster,
                remark: nil,
                year: raw.year,
                score: raw.scoreText,
                // 按请求分区回填类型，不能信返回里的 type
                typeName: channel.badge
            )
        }
    }

    /// 推荐页分区：把豆瓣条目包成 `RecommendSection`，复用现有渲染。
    static func sections(from items: [MediaItem], channel: Channel, limit: Int = 6) -> RecommendSection {
        let recommendItems = items.prefix(limit).map { item in
            RecommendItem(
                id: item.videoId,
                title: item.title,
                poster: item.poster,
                subtitle: item.metaLine,
                type: channel.badge,
                rating: Double(item.score ?? ""),
                isNew: nil,
                sourceType: nil,
                libraryId: nil,
                videoId: nil
            )
        }

        return RecommendSection(title: channel.title, type: channel.type, items: recommendItems)
    }
}

// MARK: - 豆瓣原始结构

struct DoubanRawPage: Decodable {
    /// `recent_hot` 用 `items`
    let items: [DoubanRawItem]?
    /// `new_search_subjects` 用 `data`
    let data: [DoubanRawItem]?
    let total: Int?
}

struct DoubanRawItem: Decodable {
    let id: String?
    let title: String?
    let year: String?
    /// 搜索接口的封面字段
    let cover: String?
    let pic: DoubanPic?
    let rating: DoubanRating?
    /// 搜索接口的评分是字符串
    let rate: String?
    /// `recent_hot` 的副标题，形如「2026 / 中国大陆 / 剧情」
    let cardSubtitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case cover
        case pic
        case rating
        case rate
        case cardSubtitle = "card_subtitle"
    }

    var posterURL: String? {
        let large = pic?.large ?? ""
        if !large.isEmpty { return large }
        let normal = pic?.normal ?? ""
        if !normal.isEmpty { return normal }
        let searchCover = cover ?? ""
        return searchCover.isEmpty ? nil : searchCover
    }

    var scoreText: String? {
        if let value = rating?.value, value > 0 {
            return String(format: "%.1f", value)
        }
        let raw = rate ?? ""
        return raw.isEmpty ? nil : raw
    }
}
