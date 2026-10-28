import SwiftUI

/// 电视 Tab（规范第 6 章）：局域网内已配对设备列表。
struct TVView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isScanning = false
    @State private var devices: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .homeBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack {
            Text("电视")
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Button {
                scan()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isScanning ? "扫描中" : "重新扫描")
                        .font(Theme.font(12))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if devices.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                EmptyHintView(
                    icon: "tv",
                    text: "还没有配对过电视。\n请确认电视已打开「手机推送」并与手机在同一网络。"
                )
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(devices, id: \.self) { name in
                        HStack {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accent)
                            Text(name)
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                                .fill(Theme.cardDeep)
                        )
                    }
                }
                .padding(.horizontal, Theme.padPage)
            }
        }
    }

    private func scan() {
        isScanning = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isScanning = false
        }
    }
}
