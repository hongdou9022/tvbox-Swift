import SwiftUI

/// 电视 Tab（规范第 6 章）：局域网内已配对设备列表。
struct TVView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var cast = CastService.shared
    @State private var selectedDevice: CastDevice?

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
            await cast.scan()
        }
        .sheet(item: $selectedDevice) { device in
            RemoteControlSheet(device: device)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.bgDetail)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("电视")
                    .font(Theme.font(17, .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("局域网内已配对 \(pairedCount) 台")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer()

            Button {
                Task { await cast.scan() }
            } label: {
                HStack(spacing: 4) {
                    if cast.isScanning {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(cast.isScanning ? "扫描中" : "重新扫描")
                        .font(Theme.font(12))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(cast.isScanning)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var pairedCount: Int {
        cast.devices.filter { cast.isPaired($0) }.count
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if cast.devices.isEmpty {
            VStack {
                Spacer()
                if cast.isScanning {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("正在查找同一网络下的电视…")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.textWeak)
                        .padding(.top, 12)
                } else {
                    EmptyHintView(
                        icon: "tv",
                        text: "还没有找到电视。\n请确认电视已打开「手机推送」并与手机在同一网络。"
                    )
                }
                Spacer()
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 9) {
                    ForEach(cast.devices) { device in
                        Button {
                            selectedDevice = device
                        } label: {
                            deviceRow(device)
                        }
                        .buttonStyle(TapScaleStyle())
                    }

                    Text("点电视进入遥控；在播放页点投屏图标可把当前内容推到电视")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.horizontal, Theme.padPage)
                .padding(.bottom, 30)
            }
        }
    }

    private func deviceRow(_ device: CastDevice) -> some View {
        let paired = cast.isPaired(device)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: "tv.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(device.ip)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer(minLength: 8)

            Text(device.statusText(paired: paired))
                .font(Theme.font(11))
                .foregroundStyle(paired ? Theme.accent : Theme.textWeak)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .fill(Theme.cardDeep)
        )
    }
}
