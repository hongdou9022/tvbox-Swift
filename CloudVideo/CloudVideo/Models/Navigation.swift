import Foundation

/// 详情页跳转目标。规范 3.4：推荐卡片只有豆瓣 id，没有可播放地址时按剧名跳搜索。
struct MediaTarget: Hashable {
    let libraryId: String
    let videoId: String
    let sourceType: String
    let title: String
    let poster: String

    init(libraryId: String, videoId: String, sourceType: String?, title: String, poster: String?) {
        self.libraryId = libraryId
        self.videoId = videoId
        self.sourceType = (sourceType?.isEmpty == false) ? sourceType! : "spider"
        self.title = title
        self.poster = poster ?? ""
    }

    /// 有没有真实可播放的定位信息。
    var isPlayable: Bool {
        !libraryId.isEmpty && !videoId.isEmpty
    }

    init(item: MediaItem) {
        self.init(
            libraryId: item.libraryId,
            videoId: item.videoId,
            sourceType: item.sourceType,
            title: item.title,
            poster: item.poster
        )
    }

    init(recommend: RecommendItem) {
        self.init(
            libraryId: recommend.libraryId ?? "",
            videoId: recommend.videoId ?? "",
            sourceType: recommend.sourceType,
            title: recommend.title,
            poster: recommend.poster
        )
    }
}

/// 按剧名跳搜索页。
struct SearchRequest: Hashable {
    let keyword: String
}

/// 页面路由。首页/搜索/我的三个栈共用同一套目标。
enum Route: Hashable {
    case detail(MediaTarget)
    case search(String)

    /// 规范 3.4：推荐卡片带的是豆瓣 id，没有可播放地址 → 按剧名跳搜索页。
    static func media(_ item: MediaItem) -> Route {
        let target = MediaTarget(item: item)
        return target.isPlayable ? .detail(target) : .search(item.title)
    }

    static func recommend(_ item: RecommendItem) -> Route {
        let target = MediaTarget(recommend: item)
        return target.isPlayable ? .detail(target) : .search(item.title)
    }
}
