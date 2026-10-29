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

/// 搜索页内容（`PHONE_UI_SPEC.md` 第 4 章 v1.14）。首页跳转时复用同一个视图。
struct SearchScreen: View {
    var initialKeyword: String = ""
    var showsBackButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focused: Bool

    @State private var showScopeMenu = false
    @State private var scopeAnchor: CGRect = .zero
    @State private var showClearHistory = false
    @State private var pendingDeleteWord: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            statusRow
            content
        }
        .homeBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onPreferenceChange(DropdownAnchorKey.self) { anchor in
            if anchor != .zero { scopeAnchor = anchor }
        }
        .overlay {
            if showScopeMenu {
                PhoneDropdown(
                    anchor: scopeAnchor,
                    options: dropdownOptions,
                    selectedId: selectedId,
                    onSelect: { option in
                        showScopeMenu = false
                        vm.applyScope(scope(for: option))
                    },
                    onDismiss: { showScopeMenu = false }
                )
            }
        }
        .phoneConfirm(
            isPresented: $showClearHistory,
            title: "清空最近搜索？",
            message: "清空后无法恢复",
            confirmTitle: "清空"
        ) {
            vm.clearHistory()
        }
        .phoneConfirm(
            isPresented: Binding(
                get: { pendingDeleteWord != nil },
                set: { if !$0 { pendingDeleteWord = nil } }
            ),
            title: "删除这条记录？",
            confirmTitle: "删除"
        ) {
            if let word = pendingDeleteWord {
                vm.removeHistory(word)
            }
            pendingDeleteWord = nil
        }
        .task {
            if vm.keyword.isEmpty { vm.keyword = initialKeyword }
            await vm.prepareIfNeeded()
            if !initialKeyword.isEmpty, !vm.hasSearched {
                vm.search()
            }
        }
        .onDisappear {
            vm.cancel()
        }
    }

    // MARK: - 顶部搜索栏

    /// 规范 4.1（v1.4）：搜索范围按钮位于**搜索框内部最左侧**，与输入框同一行。
    /// 顺序：`[全站 ▾] | 🔍 [输入框] … 🔍`
    private var searchBar: some View {
        HStack(spacing: 8) {
            if showsBackButton {
                CircleIconButton(systemName: "chevron.left", size: 36) {
                    vm.cancel()
                    dismiss()
                }
            }

            HStack(spacing: 6) {
                scopeButton

                // 按钮与放大镜之间的 1×16dp 竖分隔线
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 16)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
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
                        vm.search()
                    }

                if !vm.keyword.isEmpty {
                    Button {
                        vm.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    focused = false
                    vm.search()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 36)
            .background(Capsule(style: .continuous).fill(Theme.cardDeep))
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// 胶囊按钮 28dp 高、最大宽 88dp，文字 12sp，右侧 14dp 下箭头（旋转 90°）。
    private var scopeButton: some View {
        Button {
            focused = false
            showScopeMenu = true
        } label: {
            HStack(spacing: 2) {
                Text(vm.scope.title)
                    .font(Theme.font(12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(90))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .frame(maxWidth: 88)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropdownAnchor()
    }

    // MARK: - 下拉菜单

    private var dropdownOptions: [PhoneDropdownOption] {
        var list = [PhoneDropdownOption(id: "__all__", title: "全站")]
        for target in vm.menuTargets {
            list.append(
                PhoneDropdownOption(
                    id: target.id,
                    title: target.name,
                    badge: target.suffix
                )
            )
        }
        return list
    }

    private var selectedId: String {
        switch vm.scope {
        case .all: return "__all__"
        case .site(let id, _): return id
        case .spider(let id, _): return id
        }
    }

    private func scope(for option: PhoneDropdownOption) -> SearchScope {
        guard option.id != "__all__" else { return .all }
        if let matched = vm.menuTargets.first(where: { $0.id == option.id }) {
            return matched.kind == .site
                ? .site(id: matched.id, name: matched.name)
                : .spider(id: matched.id, name: matched.name)
        }
        return .all
    }

    // MARK: - 统计行（规范 v1.14：结果态常驻）

    @ViewBuilder
    private var statusRow: some View {
        if vm.hasSearched {
            // 固定 18dp + 单行省略，文案再长也只截断不换行，行高恒定
            Text(vm.statusLine)
                .font(Theme.font(11))
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.padPage)
                .padding(.top, 6)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !vm.hasSearched {
            emptyState
        } else if vm.hits.isEmpty {
            if vm.isSearching {
                loadingView
            } else {
                noResultView
            }
        } else {
            resultArea
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(Theme.accent)
            Text("搜索中…")
                .font(Theme.font(12))
                .foregroundStyle(Theme.textWeak)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultView: some View {
        VStack(spacing: 0) {
            EmptyHintView(icon: "magnifyingglass", text: "换个关键词试试")
            Spacer()
        }
    }

    // MARK: - 结果区（规范 4.3 v1.8：左右分栏）

    private var resultArea: some View {
        HStack(alignment: .top, spacing: 0) {
            if vm.showsSourceRail {
                sourceRail
            }
            resultList
        }
        .padding(.top, 6)
    }

    /// 左侧来源栏：宽 104dp，每项 38dp 高；选中深绿底 + 绿字。
    private var sourceRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(vm.sourceRail, id: \.key) { entry in
                    let selected = vm.selectedSourceId == entry.id
                    Button {
                        vm.selectSource(entry.id)
                    } label: {
                        Text(entry.name)
                            .font(Theme.font(11))
                            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // 放不下时逐级缩小字号（11sp → 最小 8sp）
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 6)
                            .frame(width: 104, height: 38, alignment: .center)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color(hex: 0x1F3B2E) : Color(hex: 0x22252C))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
        }
        .frame(width: 124)
    }

    /// 右侧结果区：单列横排卡片。
    private var resultList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(vm.hits) { hit in
                    NavigationLink(value: Route.media(hit.item)) {
                        SearchResultCard(hit: hit)
                    }
                    .buttonStyle(TapScaleStyle())
                }
            }
            .padding(.horizontal, vm.showsSourceRail ? 4 : Theme.padPage)
            .padding(.bottom, 24)
        }
    }

    // MARK: - 空态（规范 4.2：最近热搜 + 历史记录）

    private var emptyState: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                hotSection
                historySection
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近热搜")
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.padPage)

            if vm.hotWords.isEmpty {
                Text("暂无热播内容")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, Theme.padPage)
            } else {
                // 两列、带序号 1–6，序号按名次变色
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(Array(vm.hotWords.prefix(6).enumerated()), id: \.offset) { index, word in
                        Button {
                            focused = false
                            vm.useKeyword(word)
                        } label: {
                            HStack(spacing: 7) {
                                Text("\(index + 1)")
                                    .font(Theme.font(11, .bold))
                                    .foregroundStyle(index < 3 ? Theme.accent : Theme.textFaint)
                                    .frame(width: 12, alignment: .leading)

                                Text(word)
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史记录")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if !vm.history.isEmpty {
                    Button {
                        showClearHistory = true
                    } label: {
                        Text("清空")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.padPage)

            if vm.history.isEmpty {
                Text("搜索影片名 / 演员 / 导演")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, Theme.padPage)
            } else {
                // 胶囊标签流式排列，宽度自适应、自动换行；长按删除单条
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(vm.history, id: \.self) { word in
                        Text(word)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: 150)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(hex: 0x22252C))
                            )
                            .contentShape(Capsule())
                            .onTapGesture {
                                focused = false
                                vm.useKeyword(word)
                            }
                            .onLongPressGesture {
                                pendingDeleteWord = word
                            }
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }
}

// MARK: - 结果卡片（规范 4.3 v1.11 / v1.12）

/// 单列横排：封面左 70×96，右侧剧名 2 行 + 源名 + 集数。
///
/// 卡片**固定四行等高**：剧名单行时第二行留白，不影响卡片高度。
/// 剧名放不下时逐级缩字（15sp → 最小 11sp），最小仍不够才省略号。
struct SearchResultCard: View {
    let hit: SearchHit

    private var item: MediaItem { hit.item }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RemoteImage(urlString: item.poster ?? "", contentMode: .fill, cornerRadius: 6)
                .frame(width: 70, height: 96)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.73)
                    .frame(height: 44, alignment: .topLeading)

                Text(item.libraryName)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .frame(height: 19, alignment: .leading)

                Text(episodeText)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textWeak)
                    .lineLimit(1)
                    .frame(height: 19, alignment: .leading)

                Spacer(minLength: 0)
            }
            .frame(height: 96, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.cardDeep)
        )
    }

    private var episodeText: String {
        let remark = item.remark ?? ""
        if !remark.isEmpty { return remark }
        let type = item.typeName ?? ""
        return type.isEmpty ? "" : type
    }
}

// MARK: - 流式布局

/// 胶囊标签流式排列（规范 4.2：宽度自适应、自动换行）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let width = maxWidth.isFinite ? maxWidth : x
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
