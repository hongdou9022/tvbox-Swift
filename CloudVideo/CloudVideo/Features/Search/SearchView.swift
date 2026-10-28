import SwiftUI
import UIKit

/// 搜索页：多源并发搜索 + 历史词。
struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Video.self) { video in
                DetailView(video: video)
            }
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)

                TextField("搜索影片、演员、导演", text: $vm.keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit {
                        focused = false
                        Task { await vm.search(app: app) }
                    }

                if !vm.keyword.isEmpty {
                    Button {
                        vm.keyword = ""
                        vm.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )

            if focused || !vm.keyword.isEmpty {
                Button("取消") {
                    focused = false
                    vm.keyword = ""
                    vm.clearResults()
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if vm.isSearching {
            VStack {
                Spacer()
                LoadingRow(text: "正在多个源里找…")
                Spacer()
            }
        } else if !vm.results.isEmpty {
            resultGrid
        } else if let message = vm.message {
            ScrollView {
                EmptyStateView(icon: "magnifyingglass", title: "没找到", subtitle: message)
                    .padding(.top, 60)
            }
        } else {
            discoverPanel
        }
    }

    private var resultGrid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("找到 \(vm.results.count) 个结果")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.pagePadding)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.results) { video in
                        NavigationLink(value: video) {
                            PosterCard(video: video)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.96))
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
        }
    }

    /// 空态：历史搜索词 + 可搜索源提示。
    private var discoverPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if !vm.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近搜索")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button("清空") {
                                vm.clearHistory()
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                        }

                        FlowChips(items: vm.history) { text in
                            vm.useKeyword(text, app: app)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("正在搜索的源")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("会在 \(app.searchableSources.count) 个源里同时搜索，结果按来源去重。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)

                    ForEach(app.searchableSources.prefix(8)) { source in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Theme.accentGradient)
                                .frame(width: 6, height: 6)
                            Text(source.name)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(source.typeLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - 自动换行的标签流

/// 历史搜索词按行排布，比横向滚动更容易点中。
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    /// 按估算宽度把标签切行，避免使用 GeometryReader 带来的高度塌陷。
    private var rows: [[String]] {
        let maxWidth = UIScreen.main.bounds.width - Theme.pagePadding * 2
        var result: [[String]] = []
        var current: [String] = []
        var usedWidth: CGFloat = 0

        for item in items {
            let width = CGFloat(item.count) * 12 + 34
            if usedWidth + width > maxWidth && !current.isEmpty {
                result.append(current)
                current = [item]
                usedWidth = width
            } else {
                current.append(item)
                usedWidth += width + 8
            }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.self) { item in
                        Button {
                            onTap(item)
                        } label: {
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Theme.panelHigh))
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
