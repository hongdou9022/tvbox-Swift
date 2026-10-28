import SwiftUI
import Combine

/// 详情 / 播放页状态（规范第 5 章）。
@MainActor
final class DetailViewModel: ObservableObject {

    @Published private(set) var detail: MediaDetail?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// 当前线路（源）
    @Published private(set) var sourceIndex = 0
    /// 当前剧集
    @Published private(set) var episodeIndex = 0
    @Published private(set) var playInfo: PlayInfo?
    @Published private(set) var isLoadingPlay = false

    @Published private(set) var isFavorited = false
    private var favoriteId: String?
    /// 收藏写请求在途时，后台刷新的状态不得覆盖乐观更新（规范 5.4）。
    private var favoriteMutationInFlight = false

    /// 当前剧集的弹幕（按时间升序）。
    @Published private(set) var danmakuComments: [DanmakuComment] = []

    private let api = APIClient.shared
    private var target: MediaTarget?
    private var loadedKey = ""

    // MARK: - 派生数据

    var sources: [PlaySource] { detail?.playSources ?? [] }

    var episodes: [Episode] {
        guard sources.indices.contains(sourceIndex) else { return [] }
        return sources[sourceIndex].episodes
    }

    var currentEpisode: Episode? {
        guard episodes.indices.contains(episodeIndex) else { return nil }
        return episodes[episodeIndex]
    }

    var currentSourceName: String {
        guard sources.indices.contains(sourceIndex) else {
            return detail?.libraryName ?? ""
        }
        return sources[sourceIndex].name
    }

    /// 规范 5.3：只有一个源时整块隐藏。
    var hasMultipleSources: Bool { sources.count > 1 }

    var hasNext: Bool { episodeIndex + 1 < episodes.count }

    var playURL: String { playInfo?.url ?? "" }
    var playHeaders: [String: String] { playInfo?.header ?? [:] }
    var qualities: [PlayURLVariant] {
        let list = playInfo?.urls ?? []
        return list.isEmpty ? [] : list
    }

    var title: String { detail?.title ?? target?.title ?? "" }
    var poster: String { detail?.poster ?? target?.poster ?? "" }

    // MARK: - 加载

    func load(target: MediaTarget) async {
        self.target = target
        let key = target.libraryId + "|" + target.videoId
        guard key != loadedKey else { return }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await api.media(
                libraryId: target.libraryId,
                videoId: target.videoId,
                sourceType: target.sourceType
            )
            detail = result
            loadedKey = key

            sourceIndex = 0
            episodeIndex = 0
            await loadPlayInfo()
            await refreshFavorite()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadPlayInfo() async {
        guard let target, currentEpisode != nil else { return }

        isLoadingPlay = true
        do {
            playInfo = try await api.play(
                libraryId: target.libraryId,
                videoId: target.videoId,
                line: sourceIndex,
                episode: episodeIndex,
                sourceType: target.sourceType
            )
        } catch {
            playInfo = nil
            errorMessage = error.localizedDescription
        }
        isLoadingPlay = false

        await loadDanmaku()
    }

    /// 规范 5.2：弹幕开关默认值取自设置。
    private func loadDanmaku() async {
        guard PlayerPreferences.danmakuEnabled else {
            danmakuComments = []
            return
        }
        danmakuComments = await DanmakuService.shared.load(
            title: detail?.title ?? "",
            year: detail?.year ?? "",
            episode: currentEpisode?.name ?? ""
        )
    }

    // MARK: - 选择

    func selectSource(_ index: Int) async {
        guard sources.indices.contains(index), index != sourceIndex else { return }
        sourceIndex = index
        episodeIndex = 0
        await loadPlayInfo()
    }

    func selectEpisode(_ index: Int) async {
        guard episodes.indices.contains(index) else { return }
        guard index != episodeIndex || playInfo == nil else { return }
        episodeIndex = index
        await loadPlayInfo()
    }

    func selectVariant(_ variant: PlayURLVariant) async {
        guard !variant.url.isEmpty, variant.url != playInfo?.url else { return }
        // 清晰度切换只换地址，保留当前线路与剧集
        playInfo = PlayInfo(
            url: variant.url,
            urls: playInfo?.urls,
            header: playInfo?.header,
            flag: playInfo?.flag,
            parse: playInfo?.parse
        )
    }

    @discardableResult
    func playNext() async -> Bool {
        guard hasNext else { return false }
        episodeIndex += 1
        await loadPlayInfo()
        return true
    }

    // MARK: - 收藏（规范 5.4）

    private func refreshFavorite() async {
        guard let target else { return }
        // 有写请求在途时直接放弃本次刷新，避免把用户刚点的结果刷回去
        guard !favoriteMutationInFlight else { return }
        guard let status = try? await api.favoriteStatus(
            vodId: target.videoId,
            sourceId: target.libraryId
        ) else { return }
        isFavorited = status.isFavorited
        favoriteId = status.favorite?.id
    }

    /// 点击后立即切换图标，失败回滚。
    func toggleFavorite() async {
        guard let target, let detail else { return }

        let previous = isFavorited
        // 规范 5.4：点击瞬间先翻图标，再后台提交，失败回滚
        isFavorited.toggle()
        favoriteMutationInFlight = true

        do {
            if previous {
                if let favoriteId {
                    try await api.removeFavorite(id: favoriteId)
                }
                self.favoriteId = nil
            } else {
                try await api.addFavorite(
                    title: detail.title,
                    vodId: target.videoId,
                    sourceId: target.libraryId,
                    coverImage: detail.poster ?? "",
                    remark: detail.remark ?? "",
                    rating: Double(detail.score ?? "") ?? 0
                )
                // 需要拿回收藏记录 id，后续取消收藏要用；
                // 先释放标记，否则 refreshFavorite 会被自己的保护挡掉
                favoriteMutationInFlight = false
                await refreshFavorite()
            }
        } catch {
            isFavorited = previous
            errorMessage = error.localizedDescription
        }

        favoriteMutationInFlight = false
    }

    // MARK: - 投屏载荷

    /// 规范 5.7：推送内容包含定位信息与当前进度，电视端可直接续播。
    func castPayload(position: Double) -> CastPayload? {
        guard let target, let detail, let episode = currentEpisode else { return nil }
        return CastPayload(
            sourceType: target.sourceType,
            libraryId: target.libraryId,
            videoId: target.videoId,
            line: sourceIndex,
            episode: episodeIndex,
            episodeId: episode.playId,
            positionMs: Int64(max(position, 0) * 1000),
            title: detail.title
        )
    }

    // MARK: - 进度上报

    func saveProgress(position: Double, duration: Double) {
        guard let target, let detail, let episode = currentEpisode else { return }
        guard position > 1 else { return }

        Task {
            try? await api.saveProgress(
                libraryId: target.libraryId,
                videoId: target.videoId,
                title: detail.title,
                poster: detail.poster ?? "",
                playId: episode.playId,
                episodeName: episode.name,
                positionMs: Int64(position * 1000),
                durationMs: Int64(max(duration, 0) * 1000)
            )
        }
    }
}
