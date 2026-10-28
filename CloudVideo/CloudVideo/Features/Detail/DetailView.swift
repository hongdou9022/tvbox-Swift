import SwiftUI
import UIKit

/// 详情 / 播放页（规范第 5 章）。
struct DetailView: View {
    let target: MediaTarget

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = DetailViewModel()
    @StateObject private var player = PlayerModel()

    @State private var isFullscreen = false
    @State private var locked = false
    @State private var showInfo = false
    @State private var showCast = false
    @State private var showAllEpisodes = false

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    var body: some View {
        ZStack {
            Theme.bgDetail.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    playerBox
                    titleRow
                    infoRow
                    if vm.hasMultipleSources {
                        sourceCards
                    }
                    episodeSection
                    Color.clear.frame(height: 30)
                }
            }

            if isFullscreen {
                fullscreenLayer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.load(target: target)
        }
        .onChange(of: vm.playURL) { _, url in
            guard !url.isEmpty else { return }
            player.load(
                urlString: url,
                headers: vm.playHeaders,
                startAt: 0
            )
        }
        .onDisappear {
            vm.saveProgress(position: player.currentTime, duration: player.duration)
            player.stop()
            isFullscreen = false
            OrientationLock.portrait()
        }
        .sheet(isPresented: $showInfo) {
            DetailInfoSheet(detail: vm.detail, fallbackTitle: target.title, fallbackPoster: target.poster)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.bgDetail)
        }
        .sheet(isPresented: $showCast) {
            if let payload = vm.castPayload(position: player.currentTime) {
                CastPanel(payload: payload)
                    .presentationDetents([.height(420), .large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(Theme.bgDetail)
            } else {
                // 规范 8：未开始播放就推送
                Text("请先开始播放")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bgDetail)
                    .presentationDetents([.height(160)])
            }
        }
    }

    // MARK: - 播放区

    private var playerBox: some View {
        PlayerStage(
            model: player,
            title: vm.title,
            episodeName: vm.currentEpisode?.name ?? "",
            qualities: vm.qualities,
            isFullscreen: $isFullscreen,
            locked: $locked,
            onBack: {
                dismiss()
            },
            onCast: {
                showCast = true
            },
            onQuality: { variant in
                Task { await vm.selectVariant(variant) }
            },
            onNext: nextAction,
            onToggleFullscreen: {
                enterFullscreen()
            },
            onProgress: { position, duration in
                vm.saveProgress(position: position, duration: duration)
            },
            danmaku: vm.danmakuComments
        )
        // 规范 5.1-1：16:9，高 = 屏宽 × 9/16
        .frame(height: screenWidth * 9 / 16)
    }

    private var nextAction: (() -> Void)? {
        guard vm.hasNext else { return nil }
        return {
            Task { await vm.playNext() }
        }
    }

    private var fullscreenLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerStage(
                model: player,
                title: vm.title,
                episodeName: vm.currentEpisode?.name ?? "",
                qualities: vm.qualities,
                isFullscreen: .constant(true),
                locked: $locked,
                onBack: {
                    exitFullscreen()
                },
                onCast: {
                    showCast = true
                },
                onQuality: { variant in
                    Task { await vm.selectVariant(variant) }
                },
                onNext: nextAction,
                onToggleFullscreen: {
                    exitFullscreen()
                },
                onProgress: { position, duration in
                    vm.saveProgress(position: position, duration: duration)
                },
                danmaku: vm.danmakuComments
            )
            .ignoresSafeArea()
        }
        .transition(.opacity)
        .zIndex(10)
    }

    private func enterFullscreen() {
        locked = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isFullscreen = true
        }
        OrientationLock.landscape()
    }

    /// 规范 5.6：返回键先退出全屏；退出全屏后必须回到竖屏。
    private func exitFullscreen() {
        locked = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isFullscreen = false
        }
        OrientationLock.portrait()
    }

    // MARK: - 标题行

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(vm.title)
                .font(Theme.fontTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // 规范 5.4：未收藏白色空心，已收藏实心橙色，点击立即切换
            Button {
                Task { await vm.toggleFavorite() }
            } label: {
                Image(systemName: vm.isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(vm.isFavorited ? Theme.playAccent : Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 14)
    }

    // MARK: - 信息行

    private var infoRow: some View {
        HStack(spacing: 0) {
            // 规范 5.1-3：只有来源名是绿色，其余灰色
            Text("源：")
                .font(Theme.font(12))
                .foregroundStyle(Theme.textWeak)

            Text(vm.currentSourceName.isEmpty ? "未知" : vm.currentSourceName)
                .font(Theme.font(12))
                .foregroundStyle(Theme.accent)

            Text(actorSuffix)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                showInfo = true
            } label: {
                HStack(spacing: 2) {
                    Text("详情")
                        .font(Theme.font(12))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.textWeak)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 8)
    }

    private var actorSuffix: String {
        guard let actors = vm.detail?.actors, !actors.isEmpty else { return "" }
        return " | \(actors)"
    }

    // MARK: - 多源卡片（规范 5.3）

    private var sourceCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Array(vm.sources.enumerated()), id: \.element.id) { index, source in
                    let selected = vm.sourceIndex == index

                    Button {
                        Task { await vm.selectSource(index) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .font(Theme.font(12, selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                                .lineLimit(1)

                            Text("共\(source.episodes.count)集")
                                .font(Theme.fontBadge)
                                .foregroundStyle(selected ? Theme.accent.opacity(0.8) : Theme.textFaint)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                                .fill(selected ? Theme.accent.opacity(0.12) : Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                                .stroke(selected ? Theme.accent : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.padPage)
        }
        .padding(.top, 14)
    }

    // MARK: - 剧集（规范 5.1-5/6）

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("剧集列表")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("共 \(vm.episodes.count) 集")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.accent)

                Spacer()

                if vm.episodes.count > 20 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllEpisodes.toggle()
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(showAllEpisodes ? "收起" : "查看全部")
                                .font(Theme.font(11))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showAllEpisodes ? -90 : 0))
                        }
                        .foregroundStyle(Theme.textWeak)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.padPage)

            if vm.episodes.isEmpty {
                ListFooterView(state: .empty)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(visibleEpisodes) { episode in
                        let selected = episode.id == vm.currentEpisode?.id

                        Button {
                            if let index = vm.episodes.firstIndex(of: episode) {
                                Task { await vm.selectEpisode(index) }
                            }
                        } label: {
                            Text(episode.name)
                                .font(Theme.font(12, selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .white : Theme.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radiusEpisode, style: .continuous)
                                        .fill(selected ? Theme.playAccent : Theme.card)
                                )
                        }
                        .buttonStyle(TapScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
        .padding(.top, 18)
    }

    private var visibleEpisodes: [Episode] {
        if showAllEpisodes || vm.episodes.count <= 20 {
            return vm.episodes
        }
        return Array(vm.episodes.prefix(20))
    }
}
