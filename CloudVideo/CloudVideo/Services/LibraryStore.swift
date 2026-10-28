import Foundation

/// 一条观看记录。
struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: String
    var video: Video
    var lineName: String
    var episodeIndex: Int
    var episodeName: String
    var progress: Double
    var duration: Double
    var updatedAt: Date

    /// 进度百分比，0...1。
    var ratio: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }

    var progressText: String {
        if progress <= 0 { return "未开始" }
        let total = Int(progress)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "已看 %02d:%02d", minutes, seconds)
    }
}

/// 收藏与观看历史。
///
/// 直接用 JSON 文件落盘而不是 SwiftData：数据量很小（几百条），
/// 序列化简单，也不会因为模型迁移在升级时丢数据。
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [Video] = []
    @Published private(set) var history: [HistoryEntry] = []

    /// 最多保留的历史条数。
    private let maxHistory = 200

    private var favoritesURL: URL { Self.directory.appendingPathComponent("favorites.json") }
    private var historyURL: URL { Self.directory.appendingPathComponent("history.json") }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("CloudVideo", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private init() {
        favorites = Self.read([Video].self, from: favoritesURL) ?? []
        history = Self.read([HistoryEntry].self, from: historyURL) ?? []
    }

    // MARK: - 收藏

    func isFavorite(_ video: Video) -> Bool {
        favorites.contains { $0.id == video.id && $0.sourceKey == video.sourceKey }
    }

    func toggleFavorite(_ video: Video) {
        if let index = favorites.firstIndex(where: { $0.id == video.id && $0.sourceKey == video.sourceKey }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        persistFavorites()
        Haptics.tap()
    }

    func removeFavorite(_ video: Video) {
        favorites.removeAll { $0.id == video.id && $0.sourceKey == video.sourceKey }
        persistFavorites()
    }

    // MARK: - 历史

    func historyEntry(for video: Video) -> HistoryEntry? {
        history.first { $0.video.id == video.id && $0.video.sourceKey == video.sourceKey }
    }

    func record(
        video: Video,
        lineName: String,
        episodeIndex: Int,
        episodeName: String,
        progress: Double,
        duration: Double
    ) {
        let id = video.sourceKey + "|" + video.id
        // 关闭播放器时拿不到时长，沿用上一次记录的值，避免进度条被清零
        let previousDuration = history.first { $0.id == id }?.duration ?? 0
        let finalDuration = duration > 0 ? duration : previousDuration

        let entry = HistoryEntry(
            id: id,
            video: video,
            lineName: lineName,
            episodeIndex: episodeIndex,
            episodeName: episodeName,
            progress: progress,
            duration: finalDuration,
            updatedAt: Date()
        )

        history.removeAll { $0.id == id }
        history.insert(entry, at: 0)

        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
        persistHistory()
    }

    func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    // MARK: - 落盘

    private func persistFavorites() {
        Self.write(favorites, to: favoritesURL)
    }

    private func persistHistory() {
        Self.write(history, to: historyURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
