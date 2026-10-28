import SwiftUI

/// 直播 Tab（规范第 6 章）：IPTV 频道分组 + 直播间。
struct LiveView: View {
    @StateObject private var vm = LiveViewModel()
    @StateObject private var player = PlayerModel()

    @State private var playing: LiveChannel?
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
        .fullScreenCover(item: $playing) { channel in
            livePlayer(channel)
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
        if vm.isLoading && vm.channels.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            }
        } else if vm.channels.isEmpty {
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
                .padding(.bottom, 24)
            }
        }
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

    private func livePlayer(_ channel: LiveChannel) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerStage(
                model: player,
                title: channel.name,
                episodeName: channel.group,
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
        .id(channel.id)
        .onAppear {
            OrientationLock.landscape()
            player.load(urlString: channel.url, headers: [:], startAt: 0)
        }
        .onDisappear {
            player.stop()
            OrientationLock.portrait()
        }
    }

    private func play(_ channel: LiveChannel) {
        Haptics.tap()
        playing = channel
    }
}
