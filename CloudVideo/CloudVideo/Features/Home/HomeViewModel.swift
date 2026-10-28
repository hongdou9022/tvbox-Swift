import SwiftUI
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var categories: [VideoCategory] = []
    @Published private(set) var featured: [Video] = []
    @Published private(set) var videos: [Video] = []
    @Published var selectedCategory: VideoCategory?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorText: String?

    private var page = 1
    private var pageCount = 1
    /// 记录已加载的源，避免重复请求。
    private var loadedSourceKey = ""

    var hasMore: Bool { page < pageCount }

    /// 只有源发生变化时才重新加载。
    func loadIfNeeded(app: AppState) async {
        guard let source = app.currentSource else { return }
        guard source.key != loadedSourceKey else { return }
        await reload(app: app)
    }

    func reload(app: AppState) async {
        guard let source = app.currentSource else { return }

        loadedSourceKey = source.key
        isLoading = true
        errorText = nil

        do {
            let result = try await VodService.shared.home(for: source)
            categories = result.categories
            featured = result.featured

            // 默认选中第一个真实分类（推荐位单独展示，不进 tab）
            if let first = categories.first {
                selectedCategory = first
                let pageData = try await VodService.shared.videos(for: source, category: first, page: 1)
                videos = pageData.videos
                page = 1
                pageCount = pageData.pageCount
            } else {
                selectedCategory = nil
                videos = result.featured
                page = 1
                pageCount = 1
            }
        } catch {
            errorText = error.localizedDescription
            videos = []
            categories = []
            featured = []
        }

        isLoading = false
    }

    func select(_ category: VideoCategory, app: AppState) async {
        guard let source = app.currentSource else { return }
        guard selectedCategory?.id != category.id else { return }

        selectedCategory = category
        videos = []
        isLoading = true
        errorText = nil
        page = 1

        do {
            let pageData = try await VodService.shared.videos(for: source, category: category, page: 1)
            videos = pageData.videos
            pageCount = pageData.pageCount
        } catch {
            errorText = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentItem: Video, app: AppState) async {
        guard let source = app.currentSource, let category = selectedCategory else { return }
        guard hasMore, !isLoadingMore else { return }

        // 距离末尾还有 4 个时开始预加载
        guard let index = videos.firstIndex(of: currentItem), index >= videos.count - 4 else { return }

        isLoadingMore = true
        let nextPage = page + 1

        do {
            let pageData = try await VodService.shared.videos(for: source, category: category, page: nextPage)
            let existing = Set(videos.map { $0.id })
            videos.append(contentsOf: pageData.videos.filter { !existing.contains($0.id) })
            page = nextPage
            pageCount = pageData.pageCount
        } catch {
            // 加载更多失败不打断已有内容，静默处理
        }

        isLoadingMore = false
    }
}
