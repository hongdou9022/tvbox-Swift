import SwiftUI
import Combine

/// 我的（规范第 7 章）：账号信息、继续观看、收藏、设置入口。
@MainActor
final class MineViewModel: ObservableObject {
    @Published private(set) var resume: [ResumeItem] = []
    @Published private(set) var favorites: [FavoriteRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        errorMessage = nil

        async let resumeTask = api.resume(limit: 12)
        async let favoriteTask = api.favorites()

        let resumeItems = try? await resumeTask
        let favoritePage = try? await favoriteTask

        resume = resumeItems ?? []
        favorites = favoritePage?.list ?? []

        isLoading = false
    }
}

struct MineView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = MineViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.sectionGap) {
                    accountHeader
                    if !vm.resume.isEmpty {
                        resumeSection
                    }
                    if !vm.favorites.isEmpty {
                        favoriteSection
                    }
                    if vm.resume.isEmpty && vm.favorites.isEmpty && !vm.isLoading {
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
                            resumeCard(item)
                        }
                        .buttonStyle(TapScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private func resumeCard(_ item: ResumeItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(width: 108, height: 62)
                .overlay {
                    RemoteImage(urlString: item.poster ?? "", contentMode: .fill, cornerRadius: 8)
                }
                .overlay(alignment: .bottom) {
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.45)
                        Capsule()
                            .fill(Theme.playAccent)
                            .frame(width: max(2, 108 * item.progressRatio), height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.title)
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(item.episodeName ?? "继续播放")
                .font(Theme.font(10))
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)
        }
        .frame(width: 108, alignment: .leading)
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

    // MARK: - 收藏

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "收藏", trailing: "\(vm.favorites.count)")
                .padding(.horizontal, Theme.padPage)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.padGrid),
                    GridItem(.flexible(), spacing: Theme.padGrid),
                    GridItem(.flexible(), spacing: Theme.padGrid)
                ],
                spacing: 14
            ) {
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
