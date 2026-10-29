import SwiftUI
import Combine

/// 电视遥控页（接口规范 4.14.6 的 `/v2/state` + `/v2/command`）。
///
/// 只走局域网直连，不涉及推送；断线时提示，不阻塞其他功能。
struct RemoteControlSheet: View {
    let device: CastDevice

    @StateObject private var cast = CastService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var state: CastService.RemoteState?
    @State private var statusLine: String?
    @State private var pairs: [DevicePair] = []
    @State private var searchKeyword = ""
    @State private var pendingRemove: DevicePair?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header
                nowPlaying
                dpad
                playbackRow
                seekRow
                searchRow
                pairSection
            }
            .padding(.horizontal, Theme.padSheet)
            .padding(.bottom, 30)
        }
        .detailBackground()
        .onAppear {
            Task { await refreshState() }
            Task { await loadPairs() }
        }
        .onReceive(timer) { _ in
            Task { await refreshState() }
        }
        .phoneConfirm(
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            title: "删除这条配对？",
            message: "删除后这台手机需要重新在电视上确认。",
            confirmTitle: "删除"
        ) {
            if let pair = pendingRemove {
                Task { await removePair(pair) }
            }
            pendingRemove = nil
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 6) {
            SheetGrabber()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(Theme.font(16, .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(device.ip) · \(device.statusText(paired: cast.isPaired(device)))")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textWeak)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 当前播放

    private var nowTitle: String {
        if let title = state?.title, !title.isEmpty { return title }
        return "电视没有在播放"
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nowTitle)
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 2)
                    Capsule()
                        .fill(Theme.playAccent)
                        .frame(width: max(2, geo.size.width * (state?.progressRatio ?? 0)), height: 2)
                }
                .frame(height: 2)
            }
            .frame(height: 2)

            HStack {
                Text(state?.statusText ?? "连接中…")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textWeak)

                Spacer()

                if let state, state.count > 0 {
                    Text("第 \(max(state.index, 0) + 1)/\(state.count) 集")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.cardDeep)
        )
    }

    // MARK: - 方向键

    private var dpad: some View {
        VStack(spacing: 8) {
            commandButton("chevron.up", command: .up)
            HStack(spacing: 8) {
                commandButton("chevron.left", command: .left)
                commandButton("circle.circle", command: .ok)
                commandButton("chevron.right", command: .right)
            }
            commandButton("chevron.down", command: .down)
            commandButton("arrow.uturn.backward", command: .back, wide: true)
        }
    }

    private func commandButton(_ icon: String, command: CastService.RemoteCommand, wide: Bool = false) -> some View {
        Button {
            send(command)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: wide ? 190 : 58, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.card)
                )
        }
        .buttonStyle(TapScaleStyle())
    }

    // MARK: - 播放控制

    private var playbackRow: some View {
        HStack(spacing: 8) {
            commandButton("backward.end", command: .prev)
            commandButton("playpause", command: .toggle)
            commandButton("forward.end", command: .next)
        }
    }

    private var seekRow: some View {
        HStack(spacing: 8) {
            Button {
                send(.backward, value: 5000)
            } label: {
                Text("后退 5 秒")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                            .fill(Theme.cardDeep)
                    )
            }
            .buttonStyle(.plain)

            Button {
                send(.forward, value: 5000)
            } label: {
                Text("前进 5 秒")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                            .fill(Theme.cardDeep)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 在电视上搜索

    private var searchRow: some View {
        HStack(spacing: 8) {
            TextField("在电视上搜索影片", text: $searchKeyword)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.cardDeep)
                )

            Button {
                let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !keyword.isEmpty else { return }
                Task {
                    let error = await cast.searchOnTV(keyword, device: device)
                    statusLine = error
                }
            } label: {
                Text("搜索")
                    .font(Theme.font(12, .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 38)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 配对管理

    private var pairSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已配对的手机")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.textWeak)
                Spacer()
                Text("\(pairs.count)")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
            }

            if pairs.isEmpty {
                Text("还没有其他手机配对过")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(pairs) { pair in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.displayName)
                                    .font(Theme.font(13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                Text(pair.lastUsedAt ?? pair.createdAt ?? "")
                                    .font(Theme.font(10))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if pair.phoneId == cast.phoneId {
                                Text("本机")
                                    .font(Theme.font(10))
                                    .foregroundStyle(Theme.accent)
                            }

                            Button {
                                pendingRemove = pair
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0xFF6B6B))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)

                        if pair.id != pairs.last?.id {
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.cardDeep)
                )
            }

            if let statusLine {
                Text(statusLine)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.playAccent)
            }
        }
    }

    // MARK: - 动作

    private func send(_ command: CastService.RemoteCommand, value: Int? = nil) {
        Haptics.tap()
        Task {
            let error = await cast.sendCommand(command, value: value, to: device)
            statusLine = error
            await refreshState()
        }
    }

    private func refreshState() async {
        let next = try? await cast.fetchState(for: device)
        if next != nil {
            state = next
        }
    }

    private func loadPairs() async {
        let list = try? await cast.pairs(for: device.deviceId)
        pairs = list ?? []
    }

    private func removePair(_ pair: DevicePair) async {
        try? await cast.removePair(deviceId: device.deviceId, phoneId: pair.phoneId)
        await loadPairs()
    }
}
