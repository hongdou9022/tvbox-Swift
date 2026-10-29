import SwiftUI
import Combine

/// 首页状态（规范第 3 章 + 接口规范 6.1「本地直连优先」）。
///
/// 数据来源优先级：
/// - 推荐页：豆瓣直连 → `/api/app/v1/recommend` 兜底
/// - 分类页：豆瓣直连 → `/api/app/v1/category` 兜底
/// - 横幅：`/api/proxy/tencent-banner-data` → 首个分区的条目兜底
@MainActor
final class HomeViewModel: ObservableObject {

    /// 规范 3.1：频道栏固定五项。
    enum Channel: String, CaseIterable, Identifiable {
        case recommend = "推荐"
        case tv = "电视剧"
        case movie = "电影"
        case anime = "动漫"
        case variety = "综艺"

        var id: String { rawValue }
        var isRecommend: Bool { self == .recommend }

        var douban: DoubanService.Channel? {
            switch self {
            case .recommend: return nil
            case .tv: return .tv
            case .movie: return .movie
            case .anime: return .anime
            case .variety: return .variety
            }
        }
    }

    @Published var channel: Channel = .recommend

    @Published private(set) var banners: [RecommendItem] = []
    @Published private(set) var sections: [RecommendSection] = []
    @Published private(set) var gridItems: [MediaItem] = []

    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var reachedEnd = false
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private var page = 0
    private var didLoad = false

    /// 首屏需要铺满一屏，按 3 列估算约 18 个。
    private let firstScreenCount = 18

    /// 推荐页分区顺序固定（规范 3.2-2）。
    private let sectionChannels: [DoubanService.Channel] = [.tv, .movie, .anime, .variety]

    // MARK: - 首次加载

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        await loadBanners()
        await loadSections()

        isLoading = false

        if channel.isRecommend {
            return
        }
        await loadCategory(reset: true)
    }

    // MARK: - 横幅

    /// 接口规范 5.7：`isAd=true` 与空标题必须过滤；接口失败时横幅区整体隐藏。
    private func loadBanners() async {
        // tree-sitter 的 Swift 语法不支持 `if let x = try? await f()`，这里拆成两步
        let payload = try? await api.tencentBanner()
        if let items = payload?.items {
            let usable = items.filter { $0.usable }
            if !usable.isEmpty {
                banners = usable.map { item in
                    RecommendItem(
                        id: item.id ?? UUID().uuidString,
                        title: item.title ?? "",
                        poster: item.poster,
                        subtitle: item.caption,
                        type: item.type,
                        rating: nil,
                        isNew: nil,
                        sourceType: nil,
                        libraryId: nil,
                        videoId: nil
                    )
                }
                return
            }
        }

        // 兜底：用首个分区的条目补足
        banners = []
    }

    // MARK: - 推荐分区

    private func loadSections() async {
        var collected: [RecommendSection] = []

        // 豆瓣直连优先，四个分区并发
        await withTaskGroup(of: (DoubanService.Channel, [MediaItem]).self) { group in
            for channel in sectionChannels {
                group.addTask {
                    let items = await DoubanService.fetch(channel, page: 1)
                    return (channel, items)
                }
            }
            var buckets: [String: RecommendSection] = [:]
            for await (channel, items) in group {
                // 某分区无数据则整块跳过，不留空标题
                guard !items.isEmpty else { continue }
                buckets[channel.type] = DoubanService.sections(from: items, channel: channel)
            }
            collected = sectionChannels.compactMap { buckets[$0.type] }
        }

        if collected.isEmpty {
            // 豆瓣不可达 → 后端兜底
            let fallback = try? await api.recommend()
            if let list = fallback?.sections {
                collected = list.filter { !$0.items.isEmpty }
            }
        }

        sections = collected

        if banners.isEmpty, let first = collected.first {
            banners = Array(first.items.prefix(5))
        }
    }

    // MARK: - 切换频道

    func select(_ target: Channel) async {
        guard target != channel else { return }
        channel = target

        if target.isRecommend {
            return
        }
        await loadCategory(reset: true)
    }

    // MARK: - 分类页

    private func loadCategory(reset: Bool) async {
        guard let douban = channel.douban else { return }

        if reset {
            gridItems = []
            page = 0
            reachedEnd = false
            isLoading = true
        }

        do {
            var fetched = 0
            repeat {
                let next = page + 1
                let items = await DoubanService.fetch(douban, page: next)

                if items.isEmpty {
                    if page == 0 {
                        // 豆瓣不可达 → 服务端分类兜底
                        try await loadCategoryViaServer()
                    } else {
                        reachedEnd = true
                    }
                    break
                }

                page = next
                let existing = Set(gridItems.map { $0.id })
                gridItems.append(contentsOf: items.filter { !existing.contains($0.id) })
                fetched += items.count
                reachedEnd = items.count < DoubanService.pageSize

                // 规范 3.3：首屏铺满屏幕，连续拉页直到超过一屏
            } while reset && gridItems.count < firstScreenCount && !reachedEnd && fetched > 0
        } catch {
            errorMessage = error.localizedDescription
            reachedEnd = true
        }

        isLoading = false
    }

    /// 服务端分类兜底：只有它能给出可播放的 `libraryId + videoId`。
    private func loadCategoryViaServer() async throws {
        let home = try await api.home()
        let categories = home.categories ?? []
        guard let matched = categories.first(where: { $0.name == channel.rawValue })
            ?? categories.first(where: { $0.name.contains(channel.rawValue) }) else {
            reachedEnd = true
            return
        }

        let result = try await api.category(
            libraryId: matched.libraryId,
            categoryId: matched.id,
            page: 1
        )
        gridItems = result.items
        page = result.page
        reachedEnd = result.items.isEmpty || result.page >= result.pageCount
    }

    // MARK: - 滚动续页

    /// 规范 3.3：距底部不足一屏时预加载下一页。
    func loadMoreIfNeeded(currentItem: MediaItem) async {
        guard !channel.isRecommend else { return }
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        guard let index = gridItems.firstIndex(of: currentItem) else { return }
        guard index >= gridItems.count - 9 else { return }
        guard let douban = channel.douban else { return }

        isLoadingMore = true
        let items = await DoubanService.fetch(douban, page: page + 1)
        if items.isEmpty {
            reachedEnd = true
        } else {
            page += 1
            let existing = Set(gridItems.map { $0.id })
            gridItems.append(contentsOf: items.filter { !existing.contains($0.id) })
            reachedEnd = items.count < DoubanService.pageSize
        }
        isLoadingMore = false
    }
}
