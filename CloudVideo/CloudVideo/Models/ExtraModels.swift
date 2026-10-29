import Foundation

// MARK: - 豆瓣（接口规范 5.6 / 6.1）

/// 豆瓣原始结构透传：`{ "items": [...], "total": n }`。
struct DoubanPage: Decodable {
    let items: [DoubanItem]?
    let total: Int?
}

struct DoubanItem: Decodable, Hashable {
    let id: String?
    let title: String?
    let pic: DoubanPic?
    let rating: DoubanRating?

    /// 海报优先取 `large`。
    var poster: String? {
        let large = pic?.large ?? ""
        if !large.isEmpty { return large }
        let normal = pic?.normal ?? ""
        return normal.isEmpty ? nil : normal
    }

    var score: Double? { rating?.value }
}

struct DoubanPic: Decodable, Hashable {
    let large: String?
    let normal: String?
}

struct DoubanRating: Decodable, Hashable {
    let value: Double?
}

// MARK: - 首页横幅（接口规范 5.7）

struct BannerPayload: Decodable {
    let items: [BannerItem]?
    let total: Int?
}

struct BannerItem: Decodable, Hashable {
    let id: String?
    let title: String?
    let subtitle: String?
    let imageUrl: String?
    let backgroundImage: String?
    let genre: String?
    let description: String?
    let type: String?
    let isAd: Bool?

    /// 海报取 `backgroundImage`，为空才用 `imageUrl`。
    var poster: String? {
        let background = backgroundImage ?? ""
        if !background.isEmpty { return background }
        let image = imageUrl ?? ""
        return image.isEmpty ? nil : image
    }

    /// 副标题取 `subtitle`，为空用 `genre`。
    var caption: String {
        let sub = subtitle ?? ""
        if !sub.isEmpty { return sub }
        return genre ?? ""
    }

    /// `isAd=true` 与空标题必须过滤。
    var usable: Bool {
        (isAd ?? false) == false && !(title ?? "").isEmpty
    }
}

// MARK: - 观看历史（接口规范 5.2）

struct PlayHistoryPage: Decodable {
    let list: [PlayHistoryItem]?
    let total: Int?
    let page: Int?
    let pageSize: Int?
}

/// 注意：`currentProgress` / `totalDuration` 单位是**秒**，与 `/app/v1/resume` 的毫秒不同。
struct PlayHistoryItem: Decodable, Identifiable, Hashable {
    let id: String?
    let vodId: String?
    let sourceId: String?
    let sourceName: String?
    let title: String?
    let pic: String?
    let episode: String?
    let episodeName: String?
    let currentProgress: Double?
    let totalDuration: Double?
    let timestamp: Int64?
    let episodeNumber: Int?

    var key: String { id ?? (sourceId ?? "") + "|" + (vodId ?? "") }

    var progressRatio: Double {
        guard let total = totalDuration, total > 0, let current = currentProgress else { return 0 }
        return min(max(current / total, 0), 1)
    }
}

// MARK: - 追剧（接口规范 5.3）

struct WatchFollowPage: Decodable {
    let list: [WatchFollowItem]?
    let total: Int?
    let page: Int?
    let pageSize: Int?
}

struct WatchFollowItem: Decodable, Identifiable, Hashable {
    let id: String?
    let title: String?
    let posterPath: String?
    let backdropPath: String?
    let mediaType: String?
    let tmdbId: Int?
    let currentEpisodeNumber: Int?
    let nextEpisodeAirDate: String?
    let seasonNumber: Int?

    var key: String { id ?? "\(tmdbId ?? 0)-\(seasonNumber ?? 0)" }
}

// MARK: - IPTV 频道（接口规范 5.4）

struct IPTVChannelPayload: Decodable {
    let groups: [IPTVGroup]?
}

struct IPTVGroup: Decodable, Identifiable, Hashable {
    let id: String?
    let name: String
    let channels: [IPTVChannel]?

    var key: String { id ?? name }
}

struct IPTVChannel: Decodable, Identifiable, Hashable {
    let id: String?
    let name: String
    let logo: String?
    let format: String?
    let playUrls: [IPTVPlayURL]?

    var key: String { id ?? name }

    /// 第一条默认播放。
    var firstURL: String? {
        playUrls?.first?.url
    }

    var userAgent: String? {
        let ua = playUrls?.first?.ua ?? ""
        return ua.isEmpty ? nil : ua
    }
}

struct IPTVPlayURL: Decodable, Hashable {
    let url: String
    let line: String?
    let ua: String?
}

// MARK: - 直播间（接口规范 5.5）

struct LiveRoomPage: Decodable {
    let list: [LiveRoom]?
    let total: Int?
    let page: Int?
    let pageSize: Int?
}

struct LiveRoom: Decodable, Identifiable, Hashable {
    let id: String?
    let title: String?
    let roomId: String?
    let platform: String?
    let remark: String?
    let isActive: Int?
    let isDefault: Int?

    var key: String { id ?? (platform ?? "") + "/" + (roomId ?? "") }
}

struct LiveStreamInfo: Decodable {
    let platform: String?
    let roomId: String?
    let title: String?
    let anchor: String?
    let status: Int?
    let cover: String?
    let userCount: String?
    let streamUrls: [String: String]?
    let multiStreamUrls: [LiveStreamVariant]?

    enum CodingKeys: String, CodingKey {
        case platform
        case roomId = "room_id"
        case title
        case anchor
        case status
        case cover
        case userCount = "user_count"
        case streamUrls = "stream_urls"
        case multiStreamUrls = "multi_stream_urls"
    }

    var isLive: Bool { (status ?? 0) == 1 }

    /// 按支持度取第一个可用地址：hls 优先，其次 flv。
    var playURL: String? {
        guard let streamUrls else { return nil }
        for key in ["hls", "flv"] {
            if let value = streamUrls[key], !value.isEmpty { return value }
        }
        return streamUrls.values.first { !$0.isEmpty }
    }
}

struct LiveStreamVariant: Decodable {
    let quality: LiveQuality?
    let url: String?
    let format: String?
}

struct LiveQuality: Decodable {
    let name: String?
    let bitRate: Int?
    let codecType: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case bitRate = "bit_rate"
        case codecType = "codec_type"
    }
}

// MARK: - 设备配对（接口规范 4.14.7）

struct DevicePairList: Decodable {
    let pairs: [DevicePair]?
    let count: Int?
}

struct DevicePair: Decodable, Identifiable, Hashable {
    let phoneId: String
    let phoneName: String?
    let note: String?
    let createdAt: String?
    let lastUsedAt: String?

    var id: String { phoneId }

    var displayName: String {
        let note = note ?? ""
        if !note.isEmpty { return note }
        let name = phoneName ?? ""
        return name.isEmpty ? phoneId : name
    }
}
