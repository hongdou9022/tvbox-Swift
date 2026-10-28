import SwiftUI
import Combine

/// 首页状态（规范第 3 章）。
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
    private var categories: [MediaCategory] = []
    private var activeCategory: MediaCategory?
    private var page = 0
    private var pageCount = 1
    private var didLoad = false

    /// 首屏需要铺满一屏，按 3 列估算约 18 个。
    private let firstScreenCount = 18

    // MARK: - 首次加载

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            async let homeTask = api.home()
            async let recommendTask = api.recommend()

            let home = try await homeTask
            categories = home.categories ?? []

            let recommend = try await recommendTask
            applyRecommend(recommend)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false

        if channel.isRecommend {
            await loadRecommendTailIfNeeded()
        } else {
            await loadCategory(reset: true)
        }
    }

    private func applyRecommend(_ recommend: RecommendHome) {
        sections = (recommend.sections ?? []).filter { !$0.items.isEmpty }

        // 规范 3.2-1：横幅轮播。后端只给一张 banner 时，用第一个分区的条目补足，
        // 只有 1 张时轮播组件自身会停止自动切换。
        var list: [RecommendItem] = []
        if let banner = recommend.banner {
            list.append(banner)
        }
        if let first = sections.first {
            for item in first.items where list.count < 5 {
                if !list.contains(where: { $0.id == item.id }) {
                    list.append(item)
                }
            }
        }
        banners = list
    }

    /// 后端 `recommend` 可能返回空（mode 非 douban），此时退化成用首页分类首屏填充推荐区。
    private func loadRecommendTailIfNeeded() async {
        guard sections.isEmpty, let first = categories.first else { return }

        isLoading = true
        let pageData = try? await api.category(
            libraryId: first.libraryId,
            categoryId: first.id,
            page: 1
        )
        if let pageData {
            let items = pageData.items.prefix(6)
            if !items.isEmpty {
                sections = [
                    RecommendSection(
                        title: "\(first.name)推荐",
                        type: first.name,
                        items: items.map { item in
                            RecommendItem(
                                id: item.id,
                                title: item.title,
                                poster: item.poster,
                                subtitle: item.metaLine,
                                type: first.name,
                                rating: nil,
                                isNew: nil,
                                sourceType: item.sourceType,
                                libraryId: item.libraryId,
                                videoId: item.videoId
                            )
                        }
                    )
                ]
            }
        }
        isLoading = false
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

    private func category(for channel: Channel) -> MediaCategory? {
        if let exact = categories.first(where: { $0.name == channel.rawValue }) {
            return exact
        }
        return categories.first { $0.name.contains(channel.rawValue) }
    }

    private func loadCategory(reset: Bool) async {
        guard let matched = category(for: channel) else {
            activeCategory = nil
            gridItems = []
            reachedEnd = true
            return
        }

        if reset {
            activeCategory = matched
            gridItems = []
            page = 0
            pageCount = 1
            reachedEnd = false
            isLoading = true
        }

        do {
            var fetched = 0
            repeat {
                let next = page + 1
                let result = try await api.category(
                    libraryId: matched.libraryId,
                    categoryId: matched.id,
                    page: next
                )
                page = result.page
                pageCount = result.pageCount

                let existing = Set(gridItems.map { $0.id })
                gridItems.append(contentsOf: result.items.filter { !existing.contains($0.id) })
                fetched += result.items.count

                reachedEnd = page >= pageCount || result.items.isEmpty

                // 规范 3.3：首屏铺满屏幕，连续拉页直到超过一屏
            } while reset && gridItems.count < firstScreenCount && !reachedEnd && fetched > 0
        } catch {
            errorMessage = error.localizedDescription
            reachedEnd = true
        }

        isLoading = false
    }

    // MARK: - 滚动续页

    /// 规范 3.3：距底部不足一屏时预加载下一页。
    func loadMoreIfNeeded(currentItem: MediaItem) async {
        guard !channel.isRecommend else { return }
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        guard let index = gridItems.firstIndex(of: currentItem) else { return }
        guard index >= gridItems.count - 9 else { return }

        guard let matched = activeCategory else { return }

        isLoadingMore = true
        do {
            let next = page + 1
            let result = try await api.category(
                libraryId: matched.libraryId,
                categoryId: matched.id,
                page: next
            )
            page = result.page
            pageCount = result.pageCount

            let existing = Set(gridItems.map { $0.id })
            gridItems.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            reachedEnd = page >= pageCount || result.items.isEmpty
        } catch {
            reachedEnd = true
        }
        isLoadingMore = false
    }
}
