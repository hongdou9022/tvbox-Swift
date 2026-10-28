import SwiftUI
import Combine

/// 全局状态：配置加载、数据源选择、直播源。
@MainActor
final class AppState: ObservableObject {

    // MARK: - 已加载的配置

    @Published private(set) var sources: [SourceBean] = []
    @Published private(set) var liveEntries: [LiveEntry] = []
    @Published private(set) var wallpaper: String = ""

    /// 当前用于首页/搜索的主源。
    @Published var currentSource: SourceBean? {
        didSet {
            if let currentSource {
                defaults.set(currentSource.key, forKey: Keys.sourceKey)
            }
        }
    }

    // MARK: - 加载状态

    @Published private(set) var isLoading = false
    @Published private(set) var isConfigured = false
    @Published var errorText: String?
    @Published var configURL: String = ""

    private let defaults = UserDefaults.standard
    private let net = NetworkClient.shared

    private enum Keys {
        static let configURL = "cloudvideo.config.url"
        static let sourceKey = "cloudvideo.config.source"
    }

    /// 可搜索的源（已过滤掉不支持的 JAR 源）。
    var searchableSources: [SourceBean] {
        sources.filter { $0.searchable && $0.isSupported && $0.isHTTP }
    }

    var supportedSources: [SourceBean] {
        sources.filter { $0.isSupported && $0.isHTTP }
    }

    // MARK: - 启动

    /// App 启动时恢复上次的配置。
    func bootstrap() async {
        let saved = defaults.string(forKey: Keys.configURL) ?? ""
        guard !saved.isEmpty else { return }
        configURL = saved
        await loadConfig(saved)
    }

    // MARK: - 加载配置

    func loadConfig(_ url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "请输入配置地址"
            return
        }

        isLoading = true
        errorText = nil

        do {
            let parsed = try await fetchConfig(trimmed, depth: 0)

            guard !parsed.sources.isEmpty || !parsed.liveEntries.isEmpty else {
                errorText = "配置里没有可用的站点或直播源"
                isLoading = false
                return
            }

            apply(parsed, configURL: ConfigParser.normalize(trimmed))
            defaults.set(configURL, forKey: Keys.configURL)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
        }

        isLoading = false
    }

    /// 拉取并解析配置；如果是多仓库入口，自动向下展开一层。
    private func fetchConfig(_ url: String, depth: Int) async throws -> ParsedConfig {
        guard depth <= 3 else {
            throw VodError.parseFailed
        }

        let normalized = ConfigParser.normalize(url)
        let text = try await net.getString(normalized)

        guard let parsed = ConfigParser.parse(text) else {
            throw VodError.parseFailed
        }

        if !parsed.sources.isEmpty || !parsed.liveEntries.isEmpty {
            return parsed
        }

        // 多仓库入口：按顺序尝试子地址，第一个成功的就用
        for candidate in parsed.repositoryURLs {
            if let nested = try? await fetchConfig(candidate, depth: depth + 1),
               !nested.sources.isEmpty || !nested.liveEntries.isEmpty {
                return nested
            }
        }

        return parsed
    }

    private func apply(_ parsed: ParsedConfig, configURL: String) {
        self.configURL = configURL
        sources = parsed.sources
        liveEntries = parsed.liveEntries
        wallpaper = parsed.wallpaper

        let savedKey = defaults.string(forKey: Keys.sourceKey) ?? ""
        if let restored = sources.first(where: { $0.key == savedKey }), restored.isSupported {
            currentSource = restored
        } else {
            currentSource = sources.first(where: { $0.isSupported && $0.isHTTP }) ?? sources.first
        }

        isConfigured = true
    }

    // MARK: - 操作

    func selectSource(_ source: SourceBean) {
        guard source.isSupported else {
            errorText = "「\(source.name)」是 \(source.typeLabel) 源，iOS 端暂不支持"
            return
        }
        currentSource = source
        Haptics.select()
    }

    /// 清空配置，回到引导页。
    func reset() {
        defaults.removeObject(forKey: Keys.configURL)
        defaults.removeObject(forKey: Keys.sourceKey)
        sources = []
        liveEntries = []
        currentSource = nil
        configURL = ""
        isConfigured = false
        errorText = nil
    }

    /// 按 key 找回源，详情页需要用它请求数据。
    func source(for key: String) -> SourceBean? {
        if let match = sources.first(where: { $0.key == key }) { return match }
        return currentSource
    }
}
