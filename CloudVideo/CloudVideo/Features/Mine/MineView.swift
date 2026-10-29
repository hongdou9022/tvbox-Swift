import SwiftUI
import Combine

/// 我的（规范第 7 章）：账号信息、继续观看、观看历史、收藏、追剧、设置入口。
///
/// 接口分工（接口规范 5.2 / 5.3）：
/// - `/app/v1/resume`：只看未看完，时长毫秒 → 首页「继续观看」
/// - `/api/play-history`：全部历史，时长**秒** → 我的「观看历史」
/// - `/api/watch-follow`：追剧列表
@MainActor
final class MineViewModel: ObservableObject {
    @Published private(set) var resume: [ResumeItem] = []
    @Published private(set) var history: [PlayHistoryItem] = []
    @Published private(set) var favorites: [FavoriteRecord] = []
    @Published private(set) var follows: [WatchFollowItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        errorMessage = nil

        async let resumeTask = api.resume(limit: 12)
        async let historyTask = api.playHistory(pageSize: 20)
        async let favoriteTask = api.favorites()
        async let followTask = api.watchFollow(size: 20)

        let resumeItems = try? await resumeTask
        let historyPage = try? await historyTask
        let favoritePage = try? await favoriteTask
        let followPage = try? await followTask

        resume = resumeItems ?? []
        history = historyPage?.list ?? []
        favorites = favoritePage?.list ?? []
        follows = followPage?.list ?? []

        isLoading = false
    }

    func deleteHistory(_ item: PlayHistoryItem) async {
        guard let id = item.id, !id.isEmpty else { return }
        try? await api.deletePlayHistory(id: id)
        history.removeAll { $0.key == item.key }
    }
}

struct MineView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = MineViewModel()
    @State private var showSettings = false
    @State private var pendingDeleteHistory: PlayHistoryItem?

    private let columns = [
        GridItem(.flexible(), spacing: Theme.padGrid),
        GridItem(.flexible(), spacing: Theme.padGrid),
        GridItem(.flexible(), spacing: Theme.padGrid)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.sectionGap) {
                    accountHeader
                    if !vm.resume.isEmpty {
                        resumeSection
                    }
                    if !vm.history.isEmpty {
                        historySection
                    }
                    if !vm.favorites.isEmpty {
                        favoriteSection
                    }
                    if !vm.follows.isEmpty {
                        followSection
                    }
                    if isEmpty && !vm.isLoading {
                        EmptyHintView(icon: "clock", text: "还没有观看记录和收藏")
                    }
                    settingsEntry
                }
                .padding(.bottom, 30)
            }
            .homeBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .detail(let target):
                    DetailView(target: target)
                case .search(let keyword):
                    SearchScreen(initialKeyword: keyword, showsBackButton: true)
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .task {
            await vm.load()
        }
        .phoneConfirm(
            isPresented: Binding(
                get: { pendingDeleteHistory != nil },
                set: { if !$0 { pendingDeleteHistory = nil } }
            ),
            title: "删除这条观看记录？",
            confirmTitle: "删除"
        ) {
            if let item = pendingDeleteHistory {
                Task { await vm.deleteHistory(item) }
            }
            pendingDeleteHistory = nil
        }
    }

    private var isEmpty: Bool {
        vm.resume.isEmpty && vm.history.isEmpty && vm.favorites.isEmpty && vm.follows.isEmpty
    }

    // MARK: - 账号

    private var accountHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 50, height: 50)

                Text(initial)
                    .font(Theme.font(19, .bold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.user?.username ?? "已连接")
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(session.serverAddress)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textWeak)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 10)
    }

    private var initial: String {
        let name = session.user?.username ?? "U"
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - 继续观看

    private var resumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "继续观看")
                .padding(.horizontal, Theme.padPage)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.resume) { item in
                        NavigationLink(value: resumeRoute(item)) {
                            progressCard(
                                poster: item.poster,
                                title: item.title,
                                caption: item.episodeName ?? "继续播放",
                                ratio: item.progressRatio
                            )
                        }
                        .buttonStyle(TapScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private func resumeRoute(_ item: ResumeItem) -> Route {
        .detail(
            MediaTarget(
                libraryId: item.libraryId,
                videoId: item.videoId,
                sourceType: nil,
                title: item.title,
                poster: item.poster
            )
        )
    }

    // MARK: - 观看历史（接口规范 5.2）

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "观看历史", trailing: "\(vm.history.count)")
                .padding(.horizontal, Theme.padPage)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.history, id: \.key) { item in
                        NavigationLink(value: historyRoute(item)) {
                            progressCard(
                                poster: item.pic,
                                title: item.title ?? "",
                                caption: item.episodeName ?? "",
                                ratio: item.progressRatio
                            )
                        }
                        .buttonStyle(TapScaleStyle())
                        .contextMenu {
                            Button("删除这条记录", role: .destructive) {
                                pendingDeleteHistory = item
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private func historyRoute(_ item: PlayHistoryItem) -> Route {
        .detail(
            MediaTarget(
                libraryId: item.sourceId ?? "",
                videoId: item.vodId ?? "",
                sourceType: nil,
                title: item.title ?? "",
                poster: item.pic
            )
        )
    }

    /// 横版小卡 + 底部橙色进度条。
    private func progressCard(
        poster: String?,
        title: String,
        caption: String,
        ratio: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(width: 108, height: 62)
                .overlay {
                    RemoteImage(urlString: poster ?? "", contentMode: .fill, cornerRadius: 8)
                }
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.45)
                        Capsule()
                            .fill(Theme.playAccent)
                            .frame(width: max(2, 108 * ratio), height: 2)
                    }
                    .frame(height: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(caption.isEmpty ? " " : caption)
                .font(Theme.font(10))
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)
        }
        .frame(width: 108, alignment: .leading)
    }

    // MARK: - 收藏

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "收藏", trailing: "\(vm.favorites.count)")
                .padding(.horizontal, Theme.padPage)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(vm.favorites) { record in
                    NavigationLink(value: favoriteRoute(record)) {
                        MediaCard(
                            title: record.title ?? "",
                            poster: record.coverImage ?? "",
                            badge: "",
                            rating: nil,
                            meta: record.remark ?? ""
                        )
                    }
                    .buttonStyle(TapScaleStyle())
                }
            }
            .padding(.horizontal, Theme.padGrid)
        }
    }

    private func favoriteRoute(_ record: FavoriteRecord) -> Route {
        .detail(
            MediaTarget(
                libraryId: record.sourceId ?? "",
                videoId: record.vodId ?? "",
                sourceType: nil,
                title: record.title ?? "",
                poster: record.coverImage
            )
        )
    }

    // MARK: - 追剧（接口规范 5.3）

    private var followSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "追剧", trailing: "\(vm.follows.count)")
                .padding(.horizontal, Theme.padPage)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(vm.follows, id: \.key) { item in
                    // 追剧条目只有 tmdbId，没有可播放地址 → 按剧名跳搜索
                    NavigationLink(value: Route.search(item.title ?? "")) {
                        MediaCard(
                            title: item.title ?? "",
                            poster: item.posterPath ?? "",
                            badge: item.mediaType == "movie" ? "电影" : "剧集",
                            rating: nil,
                            meta: followMeta(item)
                        )
                    }
                    .buttonStyle(TapScaleStyle())
                }
            }
            .padding(.horizontal, Theme.padGrid)
        }
    }

    private func followMeta(_ item: WatchFollowItem) -> String {
        var parts: [String] = []
        if let season = item.seasonNumber, season > 0 {
            parts.append("第 \(season) 季")
        }
        if let episode = item.currentEpisodeNumber, episode > 0 {
            parts.append("更新至第 \(episode) 集")
        }
        if let date = item.nextEpisodeAirDate, !date.isEmpty {
            parts.append(date)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 设置入口

    private var settingsEntry: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                Text("设置")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.cardDeep)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.padPage)
    }
}
