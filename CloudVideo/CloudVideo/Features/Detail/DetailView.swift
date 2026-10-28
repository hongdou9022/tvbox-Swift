import SwiftUI

/// 详情页：模糊海报头图 + 信息 + 线路/选集 + 简介。
struct DetailView: View {
    let video: Video

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = DetailViewModel()
    @State private var showPlayer = false
    @State private var synopsisExpanded = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.pageGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    actionRow
                    if vm.hasLines { lineSection }
                    if !vm.episodes.isEmpty { episodeSection }
                    if let detail = vm.detail, !detail.plainContent.isEmpty { synopsisSection(detail) }
                    Color.clear.frame(height: 40)
                }
            }

            topControls
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard let source = app.source(for: video.sourceKey) else { return }
            await vm.load(video: video, source: source)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let episode = vm.currentEpisode {
                PlayerView(
                    title: video.name,
                    subtitle: "\(vm.currentLineName) · \(episode.name)",
                    urlString: episode.url,
                    startAt: vm.resumeSeconds,
                    hasNext: vm.hasNext,
                    onClose: {
                        showPlayer = false
                    },
                    onProgress: { seconds, duration in
                        vm.persistProgress(video: video, seconds: seconds, duration: duration)
                    },
                    onFinished: {
                        if !vm.playNext() {
                            showPlayer = false
                        }
                    },
                    onNext: {
                        vm.playNext()
                    }
                )
                .id(episode.id)
            }
        }
    }

    // MARK: - 顶部

    private var topControls: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 4)
    }

    // MARK: - 头图

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // 模糊背景
            RemoteImage(urlString: video.pic, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .clipped()
                .blur(radius: 26, opaque: true)
                .overlay(Color.black.opacity(0.35))

            LinearGradient(
                colors: [Color.clear, Theme.bg.opacity(0.85), Theme.bg],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)

            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(urlString: video.pic, contentMode: .fill, cornerRadius: 12)
                    .frame(width: 104, height: 156)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.title.isEmpty ? video.name : vm.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let detail = vm.detail, !detail.metaLine.isEmpty {
                        Text(detail.metaLine)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if !video.note.isEmpty {
                        Text(video.note)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 14)
        }
        .frame(height: 250)
        .padding(.top, 8)
    }

    // MARK: - 播放 / 收藏

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                if vm.episodes.isEmpty { return }
                showPlayer = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(playButtonTitle)
                }
            }
            .buttonStyle(AccentButtonStyle(height: 46))
            .disabled(vm.episodes.isEmpty)
            .opacity(vm.episodes.isEmpty ? 0.45 : 1)

            Button {
                library.toggleFavorite(video)
            } label: {
                Image(systemName: library.isFavorite(video) ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(library.isFavorite(video) ? Theme.danger : Theme.textSecondary)
                    .frame(width: 52, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .fill(Theme.panelHigh)
                    )
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 4)
    }

    private var playButtonTitle: String {
        guard let episode = vm.currentEpisode else { return "暂无片源" }
        if vm.resumeSeconds > 30 {
            return "继续观看 · \(episode.name)"
        }
        return "播放 \(episode.name)"
    }

    // MARK: - 线路

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "播放线路", trailing: "\(vm.lines.count) 条")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(vm.lines.enumerated()), id: \.element.id) { index, line in
                        Button {
                            vm.selectLine(index)
                        } label: {
                            TagChip(text: line.name, selected: vm.lineIndex == index)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 22)
    }

    // MARK: - 选集

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "选集", trailing: "共 \(vm.episodes.count) 集")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 62, maximum: 90), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                    Button {
                        vm.selectEpisode(index)
                        showPlayer = true
                    } label: {
                        Text(episode.name)
                            .font(.system(size: 12, weight: vm.episodeIndex == index ? .semibold : .regular))
                            .foregroundStyle(vm.episodeIndex == index ? Color.white : Theme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                if vm.episodeIndex == index {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Theme.accentGradient)
                                } else {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Theme.panelHigh)
                                }
                            }
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 22)
    }

    // MARK: - 简介

    private func synopsisSection(_ detail: VodDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "剧情简介")

            VStack(alignment: .leading, spacing: 8) {
                Text(detail.plainContent)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(5)
                    .lineLimit(synopsisExpanded ? nil : 4)

                if detail.plainContent.count > 80 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            synopsisExpanded.toggle()
                        }
                    } label: {
                        Text(synopsisExpanded ? "收起" : "展开全部")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 14)

            if let detail = vm.detail {
                if !detail.director.isEmpty || !detail.actor.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !detail.director.isEmpty {
                            infoRow("导演", detail.director)
                        }
                        if !detail.actor.isEmpty {
                            infoRow("主演", detail.actor)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(radius: 14)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 22)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 34, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
        }
    }
}
