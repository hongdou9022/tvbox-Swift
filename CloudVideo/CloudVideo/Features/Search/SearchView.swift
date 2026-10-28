import SwiftUI

/// 搜索 Tab。
struct SearchView: View {
    var body: some View {
        NavigationStack {
            SearchScreen(initialKeyword: "", showsBackButton: false)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let target):
                        DetailView(target: target)
                    case .search(let keyword):
                        SearchScreen(initialKeyword: keyword, showsBackButton: true)
                    }
                }
        }
    }
}

/// 搜索页内容（规范第 4 章）。首页跳转时复用同一个视图。
struct SearchScreen: View {
    var initialKeyword: String = ""
    var showsBackButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: Theme.padGrid),
        GridItem(.flexible(), spacing: Theme.padGrid)
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            scopeRow
            content
        }
        .homeBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vm.keyword.isEmpty { vm.keyword = initialKeyword }
            await vm.prepareIfNeeded()
            if !initialKeyword.isEmpty, vm.results.isEmpty {
                await vm.search()
            }
        }
    }

    // MARK: - 顶部

    private var searchHeader: some View {
        HStack(spacing: 8) {
            if showsBackButton {
                CircleIconButton(systemName: "chevron.left", size: 36) {
                    dismiss()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textFaint)

                TextField("搜索影片名/演员/导演", text: $vm.keyword)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit {
                        focused = false
                        Task { await vm.search() }
                    }

                if !vm.keyword.isEmpty {
                    Button {
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    focused = false
                    Task { await vm.search() }
                } label: {
                    Text("搜索")
                        .font(Theme.font(12, .bold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule(style: .continuous).fill(Theme.cardDeep))
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// 规范 4.1（v1.1）：搜索范围按钮独占一行，30dp 高，
    /// 右侧同行给一条 11sp 灰色速度提示。
    private var scopeRow: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    Task { await vm.applyScope(.all) }
                } label: {
                    Text(vm.scope == .all ? "✓ 全站" : "全站")
                }

                ForEach(vm.sources) { source in
                    Button {
                        Task { await vm.applyScope(.source(id: source.id, name: source.name)) }
                    } label: {
                        Text("\(source.name) \(source.suffix)")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vm.scope.title)
                        .font(Theme.font(12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                )
            }

            Text(scopeHint)
                .font(Theme.font(11))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.bottom, 10)
    }

    private var scopeHint: String {
        switch vm.scope {
        case .all: return "全站搜索会同时查询所有来源，较慢"
        case .source: return "仅搜索该来源，更快"
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if vm.isSearching {
            VStack {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            }
        } else if !vm.results.isEmpty {
            resultList
        } else if let status = vm.statusText {
            VStack(spacing: 8) {
                statusRow(status)
                EmptyHintView(icon: "magnifyingglass", text: "换个关键词试试")
            }
        } else {
            hotSection
        }
    }

    private var resultList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if let status = vm.statusText {
                    statusRow(status)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.results) { item in
                        NavigationLink(value: Route.media(item)) {
                            SearchResultCard(item: item)
                        }
                        .buttonStyle(TapScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.padPage)
                .padding(.bottom, 24)
            }
        }
    }

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11))
            .foregroundStyle(Theme.textWeak)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.padPage)
            .padding(.bottom, 8)
    }

    // MARK: - 空态（最近热搜）

    private var hotSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最近热搜")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.accent)

                    Spacer()

                    if !vm.history.isEmpty {
                        Button("清空") {
                            vm.clearHistory()
                        }
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(.horizontal, Theme.padPage)

                if vm.hotWords.isEmpty {
                    EmptyHintView(icon: "flame", text: "还没有搜索记录")
                } else {
                    // 规范 4.2：两列热搜词列表，带序号 1–6
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(vm.hotWords.prefix(6).enumerated()), id: \.offset) { index, word in
                            Button {
                                focused = false
                                Task { await vm.useKeyword(word) }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(Theme.font(11, .bold))
                                        .foregroundStyle(index < 3 ? Theme.accent : Theme.textFaint)
                                        .frame(width: 14, alignment: .leading)

                                    Text(word)
                                        .font(Theme.font(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.padPage)
                }
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - 结果卡片

/// 规范 4.3：左侧圆角海报，右侧影片名 / 来源名（绿色）/ 备注。
struct SearchResultCard: View {
    let item: MediaItem

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RemoteImage(urlString: item.poster ?? "", contentMode: .fill, cornerRadius: 6)
                .frame(width: 62, height: 88)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(Theme.font(13, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                Text(item.libraryName)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)

                if let remark = item.remark, !remark.isEmpty {
                    Text(remark)
                        .font(Theme.font(10))
                        .foregroundStyle(Theme.textWeak)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.cardDeep)
        )
    }
}
