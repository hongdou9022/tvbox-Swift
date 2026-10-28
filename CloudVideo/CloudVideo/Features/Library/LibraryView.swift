import SwiftUI

/// 我的：收藏 + 观看历史。
struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore

    @State private var tab = 0

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    statsRow
                    segmentBar
                    listContent
                }
                .padding(.bottom, 30)
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Video.self) { video in
                DetailView(video: video)
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 52, height: 52)
                    .blur(radius: 12)
                    .opacity(0.45)

                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accentGradient)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("云影视")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(app.currentSource?.name ?? "未选择源")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 10)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: "\(library.favorites.count)", label: "收藏")
            statCard(value: "\(library.history.count)", label: "观看记录")
            statCard(value: "\(app.supportedSources.count)", label: "可用源")
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .panel(radius: 14)
    }

    // MARK: - 分段

    private var segmentBar: some View {
        HStack(spacing: 4) {
            segmentButton(title: "收藏", index: 0)
            segmentButton(title: "历史", index: 1)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, Theme.pagePadding)
    }

    private func segmentButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                tab = index
            }
            Haptics.select()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == index ? .semibold : .regular))
                .foregroundStyle(tab == index ? Color.white : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if tab == index {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.accentGradient)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表

    @ViewBuilder
    private var listContent: some View {
        if tab == 0 {
            if library.favorites.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "还没有收藏",
                    subtitle: "在详情页点一下爱心就会出现在这里"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(library.favorites) { video in
                        NavigationLink(value: video) {
                            favoriteRow(video)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                        .contextMenu {
                            Button(role: .destructive) {
                                library.removeFavorite(video)
                            } label: {
                                Label("取消收藏", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        } else {
            if library.history.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "还没有观看记录",
                    subtitle: "看过的内容会自动记在这里，方便接着看"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(library.history) { entry in
                        NavigationLink(value: entry.video) {
                            historyRow(entry)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.98))
                        .contextMenu {
                            Button(role: .destructive) {
                                library.removeHistory(entry)
                            } label: {
                                Label("删除记录", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    private func favoriteRow(_ video: Video) -> some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: video.pic, contentMode: .fill, cornerRadius: 8)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 5) {
                Text(video.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(video.subtitleLine.isEmpty ? "—" : video.subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                if !video.note.isEmpty {
                    Text(video.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .panel(radius: 14)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            RemoteImage(urlString: entry.video.pic, contentMode: .fill, cornerRadius: 8)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.video.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text("\(entry.lineName) · \(entry.episodeName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: max(4, geo.size.width * entry.ratio))
                    }
                }
                .frame(height: 3)

                Text(entry.progressText)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .panel(radius: 14)
    }
}
