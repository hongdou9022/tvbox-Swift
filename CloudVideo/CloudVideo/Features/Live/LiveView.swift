import SwiftUI

/// 正在播放的直播目标（IPTV 频道与直播间共用）。
struct LivePlayTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let url: String
    let ua: String?
}

/// 直播 Tab（规范第 6 章）：IPTV 频道分组 + 直播间。
struct LiveView: View {
    @StateObject private var vm = LiveViewModel()
    @StateObject private var player = PlayerModel()

    @State private var playing: LivePlayTarget?
    @State private var locked = false

    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .homeBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await vm.loadIfNeeded()
        }
        .fullScreenCover(item: $playing) { target in
            livePlayer(target)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("直播")
                    .font(Theme.font(17, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if !vm.channels.isEmpty {
                    Text("\(vm.channels.count) 个频道")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                }
            }

            if !vm.groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.groups, id: \.self) { group in
                            Button {
                                vm.selectedGroup = group
                                Haptics.tap()
                            } label: {
                                ChipView(title: group, selected: vm.selectedGroup == group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.channels.isEmpty && vm.rooms.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            }
        } else if vm.channels.isEmpty && vm.rooms.isEmpty {
            VStack {
                Spacer()
                EmptyHintView(
                    icon: "dot.radiowaves.left.and.right",
                    text: vm.errorText ?? "还没有直播源。\n在服务端添加 IPTV 订阅后，频道会出现在这里。"
                )
                Spacer()
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    if !vm.rooms.isEmpty {
                        roomSection
                    }
                    if !vm.visibleChannels.isEmpty {
                        channelGrid
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - 直播间（接口规范 5.5）

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleBar(title: "直播间", trailing: "\(vm.rooms.count)")
                .padding(.horizontal, Theme.padPage)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.rooms, id: \.key) { room in
                        Button {
                            openRoom(room)
                        } label: {
                            roomCard(room)
                        }
                        .buttonStyle(TapScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private func roomCard(_ room: LiveRoom) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.cardDeep)
                    .frame(width: 132, height: 74)

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }

            Text(room.title ?? "未命名直播间")
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(room.remark ?? platformName(room.platform))
                .font(Theme.font(10))
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
    }

    private func platformName(_ platform: String?) -> String {
        switch platform {
        case "bilibili": return "哔哩哔哩"
        case "douyu": return "斗鱼"
        case "huya": return "虎牙"
        case "douyin": return "抖音"
        default: return "直播"
        }
    }

    private var channelGrid: some View {
        LazyVGrid(columns: columns, spacing: 9) {
            ForEach(vm.visibleChannels) { channel in
                Button {
                    play(channel)
                } label: {
                    channelCell(channel)
                }
                .buttonStyle(TapScaleStyle())
            }
        }
        .padding(.horizontal, Theme.padPage)
    }

    private func channelCell(_ channel: LiveChannel) -> some View {
        HStack(spacing: 8) {
            if let logo = channel.logo, let url = URL(string: logo), !logo.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 20, height: 20)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
            }

            Text(channel.name)
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.cardDeep)
        )
    }

    // MARK: - 播放

    private func livePlayer(_ target: LivePlayTarget) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerStage(
                model: player,
                title: target.title,
                episodeName: target.subtitle,
                qualities: [],
                isFullscreen: .constant(true),
                locked: $locked,
                onBack: {
                    playing = nil
                },
                onCast: {},
                onQuality: { _ in },
                onNext: nil,
                onToggleFullscreen: {
                    playing = nil
                },
                onProgress: { _, _ in }
            )
            .ignoresSafeArea()
        }
        .id(target.id)
        .onAppear {
            OrientationLock.landscape()
            var headers: [String: String] = [:]
            if let ua = target.ua, !ua.isEmpty {
                headers["User-Agent"] = ua
            }
            player.load(urlString: target.url, headers: headers, startAt: 0)
        }
        .onDisappear {
            player.stop()
            OrientationLock.portrait()
        }
    }

    private func play(_ channel: LiveChannel) {
        Haptics.tap()
        playing = LivePlayTarget(
            id: channel.id,
            title: channel.name,
            subtitle: channel.group,
            url: channel.url,
            ua: channel.ua
        )
    }

    /// 直播间要先取流；未开播给出提示而不是白屏（接口规范 5.5）。
    private func openRoom(_ room: LiveRoom) {
        Haptics.tap()
        Task {
            guard let url = await vm.streamURL(for: room) else {
                vm.errorText = "该直播间当前未开播"
                return
            }
            playing = LivePlayTarget(
                id: room.key,
                title: room.title ?? "直播间",
                subtitle: platformName(room.platform),
                url: url,
                ua: nil
            )
        }
    }
}
