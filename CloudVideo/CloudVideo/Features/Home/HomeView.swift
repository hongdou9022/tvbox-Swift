import SwiftUI

/// 首页（规范第 3 章）。
struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: Theme.padGrid),
        GridItem(.flexible(), spacing: Theme.padGrid),
        GridItem(.flexible(), spacing: Theme.padGrid)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchBar
                channelBar
                content
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
        }
        .task {
            await vm.loadIfNeeded()
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.search("")) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textFaint)

                    Text("搜索更多影视")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textFaint)

                    Spacer(minLength: 0)

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textWeak)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.cardDeep)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - 频道栏

    private var channelBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(HomeViewModel.Channel.allCases) { item in
                    Button {
                        Task { await vm.select(item) }
                    } label: {
                        VStack(spacing: 5) {
                            Text(item.rawValue)
                                .font(Theme.font(15, vm.channel == item ? .bold : .regular))
                                .foregroundStyle(vm.channel == item ? Theme.accent : Theme.textSecondary)

                            // 规范 3.1：选中为绿色文字 + 下方 3dp 绿色短横线（宽 18dp）
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Theme.accent)
                                .frame(width: 18, height: 3)
                                .opacity(vm.channel == item ? 1 : 0)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.padPage)
        }
        .padding(.bottom, 12)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.sections.isEmpty && vm.gridItems.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            }
        } else if let error = vm.errorMessage, vm.sections.isEmpty && vm.gridItems.isEmpty {
            EmptyHintView(icon: "wifi.exclamationmark", text: error)
        } else if vm.channel.isRecommend {
            recommendContent
        } else {
            categoryContent
        }
    }

    // MARK: - 推荐页

    private var recommendContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.sectionGap) {
                if !vm.banners.isEmpty {
                    BannerCarousel(items: vm.banners) { item in
                        openRecommend(item)
                    }
                    .padding(.horizontal, Theme.padPage)
                }

                // 规范 3.2-2：分区顺序由后端给定，空分区整块跳过
                ForEach(vm.sections) { section in
                    sectionBlock(section)
                }

                if vm.sections.isEmpty {
                    EmptyHintView(icon: "sparkles", text: "暂无推荐内容")
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await vm.reload()
        }
    }

    private func sectionBlock(_ section: RecommendSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: section.title)
                .padding(.horizontal, Theme.padPage)

            LazyVGrid(columns: columns, spacing: 14) {
                // 规范 3.2-3：每区只铺 6 个
                ForEach(section.items.prefix(6)) { item in
                    NavigationLink(value: Route.recommend(item)) {
                        MediaCard(
                            title: item.title,
                            poster: item.poster ?? "",
                            badge: item.type ?? "",
                            rating: item.rating,
                            meta: item.subtitle ?? ""
                        )
                    }
                    .buttonStyle(TapScaleStyle())
                }
            }
            .padding(.horizontal, Theme.padGrid)
        }
    }

    // MARK: - 分类页

    private var categoryContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(vm.gridItems) { item in
                    NavigationLink(value: Route.media(item)) {
                        MediaCard(
                            title: item.title,
                            poster: item.poster ?? "",
                            badge: item.typeName ?? "",
                            rating: Double(item.score ?? ""),
                            meta: item.metaLine
                        )
                    }
                    .buttonStyle(TapScaleStyle())
                    .onAppear {
                        Task { await vm.loadMoreIfNeeded(currentItem: item) }
                    }
                }
            }
            .padding(.horizontal, Theme.padGrid)

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if vm.isLoadingMore {
            ListFooterView(state: .loading)
        } else if vm.gridItems.isEmpty && !vm.isLoading {
            ListFooterView(state: .empty)
        } else if vm.reachedEnd {
            ListFooterView(state: .noMore)
        } else {
            Color.clear.frame(height: 12)
        }
    }

    // MARK: - 跳转

    private func openRecommend(_ item: RecommendItem) {
        path.append(Route.recommend(item))
    }
}
