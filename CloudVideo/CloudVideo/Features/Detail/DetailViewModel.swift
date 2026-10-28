import SwiftUI
import Combine

@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var detail: VodDetail?
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    @Published var lineIndex = 0
    @Published var episodeIndex = 0
    /// 从历史记录恢复的播放进度（秒）。
    @Published private(set) var resumeSeconds: Double = 0

    private var loadedKey = ""

    // MARK: - 派生数据

    var lines: [PlayLine] { detail?.lines ?? [] }

    var episodes: [Episode] {
        guard lines.indices.contains(lineIndex) else { return [] }
        return lines[lineIndex].episodes
    }

    var currentLineName: String {
        guard lines.indices.contains(lineIndex) else { return "" }
        return lines[lineIndex].name
    }

    var currentEpisode: Episode? {
        guard episodes.indices.contains(episodeIndex) else { return nil }
        return episodes[episodeIndex]
    }

    var hasNext: Bool {
        episodeIndex + 1 < episodes.count
    }

    var hasLines: Bool { lines.count > 1 }

    var title: String { detail?.name ?? "" }

    // MARK: - 加载

    func load(video: Video, source: SourceBean) async {
        let key = source.key + "|" + video.id
        guard key != loadedKey else { return }

        isLoading = true
        errorText = nil

        do {
            guard let result = try await VodService.shared.detail(for: source, videoID: video.id) else {
                errorText = "没有取到详情数据"
                isLoading = false
                return
            }
            detail = result
            loadedKey = key
            restoreHistory(for: video)
        } catch {
            // 失败时不写入 loadedKey，返回上一页再进来还能重试
            errorText = error.localizedDescription
        }

        isLoading = false
    }

    /// 有历史记录时恢复到上次的线路 / 剧集 / 进度。
    private func restoreHistory(for video: Video) {
        guard let entry = LibraryStore.shared.historyEntry(for: video) else { return }

        if let index = lines.firstIndex(where: { $0.name == entry.lineName }) {
            lineIndex = index
        } else {
            lineIndex = 0
        }

        if episodes.indices.contains(entry.episodeIndex) {
            episodeIndex = entry.episodeIndex
        } else {
            episodeIndex = 0
        }

        resumeSeconds = max(entry.progress, 0)
    }

    // MARK: - 交互

    func selectLine(_ index: Int) {
        guard lines.indices.contains(index), index != lineIndex else { return }
        lineIndex = index
        episodeIndex = 0
        resumeSeconds = 0
        Haptics.select()
    }

    func selectEpisode(_ index: Int) {
        guard episodes.indices.contains(index) else { return }
        episodeIndex = index
        resumeSeconds = 0
        Haptics.tap()
    }

    @discardableResult
    func playNext() -> Bool {
        guard hasNext else { return false }
        episodeIndex += 1
        resumeSeconds = 0
        return true
    }

    // MARK: - 记录进度

    func persistProgress(video: Video, seconds: Double, duration: Double) {
        guard detail != nil else { return }
        LibraryStore.shared.record(
            video: video,
            lineName: currentLineName,
            episodeIndex: episodeIndex,
            episodeName: currentEpisode?.name ?? "第\(episodeIndex + 1)集",
            progress: seconds,
            duration: duration
        )
    }
}
