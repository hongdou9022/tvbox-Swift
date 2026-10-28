import Foundation

// MARK: - 统一响应封装

/// 后端 `models.ApiResponse`：`{code, message, data, success}`。
struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
    let success: Bool
}

// MARK: - 账号

struct AppUser: Decodable, Hashable {
    let id: String?
    let username: String?
    let role: String?
}

struct LoginResponse: Decodable {
    let token: String
    let expiresAt: Int64?
    let user: AppUser?
}

// MARK: - 首页

/// 媒体库（后端 `AppLibrary`）。
struct MediaLibrary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let searchable: Bool?
    let homeCategory: Bool?
}

/// 分类（后端 `AppCategory`）。
struct MediaCategory: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let libraryId: String
    let libraryName: String

    /// 不同媒体库可能有同名分类 ID，拼接后才是全局唯一。
    var key: String { libraryId + "|" + id }
}

/// 列表条目（后端 `AppMediaItem`）。
struct MediaItem: Decodable, Identifiable, Hashable {
    let sourceType: String?
    let libraryId: String
    let libraryName: String
    let videoId: String
    let title: String
    let poster: String?
    let remark: String?
    let year: String?
    let score: String?
    let typeName: String?

    var id: String { libraryId + "|" + videoId }

    /// 规范 3.4：影片名下方一行 `2026 / 中国大陆 / 剧情 / 导演 / 主演`。
    var metaLine: String {
        [year, typeName, remark]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }
}

/// 继续观看（后端 `AppResumeItem`）。
struct ResumeItem: Decodable, Identifiable, Hashable {
    let libraryId: String
    let libraryName: String
    let videoId: String
    let title: String
    let poster: String?
    let playId: String?
    let episodeName: String?
    let positionMs: Int64?
    let durationMs: Int64?
    let updatedAt: Int64?

    var id: String { libraryId + "|" + videoId }

    var progressRatio: Double {
        guard let duration = durationMs, duration > 0, let position = positionMs else { return 0 }
        return min(max(Double(position) / Double(duration), 0), 1)
    }
}

/// 推荐位条目（后端 `AppRecommendItem`）。
struct RecommendItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let poster: String?
    let subtitle: String?
    let type: String?
    let rating: Double?
    let isNew: Bool?
    let sourceType: String?
    let libraryId: String?
    let videoId: String?
}

struct RecommendSection: Decodable, Identifiable, Hashable {
    let title: String
    let type: String?
    let items: [RecommendItem]

    var id: String { title }
}

/// 推荐首页（后端 `AppRecommendHome`）。
struct RecommendHome: Decodable {
    let mode: String?
    let showBanner: Bool?
    let banner: RecommendItem?
    let sections: [RecommendSection]?
}

/// 首页聚合（后端 `AppHome`）。
struct HomePayload: Decodable {
    let homeMode: String?
    let libraries: [MediaLibrary]?
    let categories: [MediaCategory]?
    let resume: [ResumeItem]?
    let recommend: [RecommendItem]?
}

// MARK: - 分类分页

struct CategoryPage: Decodable {
    let items: [MediaItem]
    let page: Int
    let pageCount: Int
    let total: Int
}

// MARK: - 详情

struct Episode: Decodable, Identifiable, Hashable {
    let index: Int
    let name: String
    let playId: String

    var id: String { playId.isEmpty ? "\(index)" : playId }
}

struct PlaySource: Decodable, Identifiable, Hashable {
    let index: Int
    let name: String
    let episodes: [Episode]

    var id: Int { index }
}

struct MediaDetail: Decodable {
    let sourceType: String?
    let libraryId: String
    let libraryName: String
    let videoId: String
    let title: String
    let poster: String?
    let content: String?
    let year: String?
    let area: String?
    let actors: String?
    let director: String?
    let remark: String?
    let score: String?
    let playSources: [PlaySource]?

    /// 规范 5.5-4：概要需要过滤 HTML 标签。
    var plainContent: String {
        (content ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var metaLine: String {
        [year, area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 播放

struct PlayURLVariant: Decodable, Hashable {
    let name: String?
    let url: String
}

struct PlayInfo: Decodable {
    let url: String
    let urls: [PlayURLVariant]?
    let header: [String: String]?
    let flag: String?
    let parse: Int?
}

// MARK: - 搜索

struct SearchSource: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?

    /// 规范 4.1：站类标 `· 站`，爬虫类标 `· 源`。
    var suffix: String {
        type == "site" ? "· 站" : "· 源"
    }
}

struct SearchPage: Decodable {
    let items: [MediaItem]
    let page: Int
    let pageCount: Int
    let total: Int
}

// MARK: - 收藏

struct FavoriteRecord: Decodable, Hashable, Identifiable {
    let id: String?
    let title: String?
    let vodId: String?
    let sourceId: String?
    let coverImage: String?
    let remark: String?

    var key: String { id ?? (vodId ?? "") + "|" + (sourceId ?? "") }
}

struct FavoriteStatus: Decodable {
    let isFavorited: Bool
    let favorite: FavoriteRecord?
}

struct FavoriteListPage: Decodable {
    let list: [FavoriteRecord]
    let total: Int?
}

// MARK: - 直播（IPTV）

/// 后端 `models.IPTV`：`url` 与 `content` 二选一，`content` 是内嵌的 m3u/txt 文本。
struct IPTVSource: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let url: String?
    let content: String?
    let type: String?
    let isActive: Int?
    let isDefault: Int?
    let header: [String: String]?

    /// 频道解析优先用内嵌内容，避免多一次网络请求。
    var inlineContent: String? {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    var remoteURL: String? {
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }
}

// MARK: - 弹幕

struct DanmakuFile: Decodable, Hashable {
    let name: String?
    let url: String
}

/// 一条弹幕。`time` 为秒，`mode` 参考 B 站：1-3 滚动、4 底部、5 顶部。
struct DanmakuComment: Identifiable, Hashable {
    let id: String
    let time: Double
    let text: String
    let color: UInt32
    let mode: Int
}
