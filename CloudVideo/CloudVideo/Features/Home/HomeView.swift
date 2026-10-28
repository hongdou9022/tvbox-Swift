import SwiftUI

/// 首页：顶部源切换 + 推荐位 + 分类横滑 + 海报瀑布流。
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = HomeViewModel()
    @State private var showSourcePicker = false

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                content
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Video.self) { video in
                DetailView(video: video)
            }
        }
        .task {
            await vm.loadIfNeeded(app: app)
        }
        .onChange(of: app.currentSource) { _, _ in
            Task { await vm.reload(app: app) }
        }
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.bgRaised)
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                showSourcePicker = true
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 7, height: 7)

                    Text(app.currentSource?.name ?? "云影视")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(PressScaleStyle(scale: 0.96))

            Spacer()

            CircleIconButton(systemName: "arrow.clockwise") {
                Task { await vm.reload(app: app) }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.videos.isEmpty && vm.featured.isEmpty {
            VStack {
                Spacer()
                LoadingRow(text: "正在连接片源")
                Spacer()
            }
        } else if let error = vm.errorText, vm.videos.isEmpty, vm.featured.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "这个源暂时连不上",
                    subtitle: error,
                    actionTitle: "重试"
                ) {
                    Task { await vm.reload(app: app) }
                }
                .padding(.top, 60)
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    if !vm.featured.isEmpty {
                        heroSection
                    }

                    Section {
                        gridSection
                    } header: {
                        categoryBar
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await vm.reload(app: app)
            }
        }
    }

    // MARK: - 推荐位

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "本周热门", trailing: "\(vm.featured.count) 部")

            TabView {
                ForEach(vm.featured.prefix(6)) { video in
                    NavigationLink(value: video) {
                        HeroCard(video: video)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.985))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(height: 186)
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    // MARK: - 分类条

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.categories) { category in
                    Button {
                        Haptics.select()
                        Task { await vm.select(category, app: app) }
                    } label: {
                        TagChip(
                            text: category.name,
                            selected: vm.selectedCategory?.id == category.id
                        )
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)
        }
        .background(Theme.bg.opacity(0.96))
    }

    // MARK: - 网格

    private var gridSection: some View {
        Group {
            if vm.videos.isEmpty {
                EmptyStateView(
                    icon: "film.stack",
                    title: "这个分类还没有内容",
                    subtitle: "换个分类或源试试"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.videos) { video in
                        NavigationLink(value: video) {
                            PosterCard(video: video)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.96))
                        .onAppear {
                            Task { await vm.loadMoreIfNeeded(currentItem: video, app: app) }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)

                if vm.isLoadingMore {
                    LoadingRow(text: "加载更多")
                } else if !vm.hasMore && vm.videos.count > 12 {
                    Text("— 已经到底了 —")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 18)
                }
            }
        }
    }
}

// MARK: - 源选择

struct SourcePickerSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(app.sources) { source in
                        row(for: source)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Theme.bgRaised)
            .navigationTitle("切换数据源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func row(for source: SourceBean) -> some View {
        Button {
            app.selectSource(source)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(source.isSupported ? Theme.textPrimary : Theme.textTertiary)

                    Text(source.isSupported ? source.typeLabel : "\(source.typeLabel) · 暂不支持")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if app.currentSource?.key == source.key {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .disabled(!source.isSupported)
    }
}
