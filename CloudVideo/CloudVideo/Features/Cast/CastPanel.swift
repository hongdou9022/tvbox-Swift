import SwiftUI

/// 推送到电视浮窗（规范 5.7）。以底部面板形式浮在当前页，不跳转页面。
struct CastPanel: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case scanning
        case empty
    }

    @State private var phase: Phase = .scanning

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            Text("推送到电视")
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.textPrimary)

            Text(hintText)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textWeak)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.padSheet)
                .padding(.top, 8)

            Spacer(minLength: 0)

            if phase == .scanning {
                ProgressView()
                    .tint(Theme.accent)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.textFaint)
                    Text("没找到电视")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textWeak)
                }
            }

            Spacer(minLength: 0)

            Button {
                rescan()
            } label: {
                Text("重新扫描")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.padSheet)
            .padding(.bottom, 26)
        }
        .background(Theme.bgDetail)
        .onAppear { rescan() }
    }

    private var hintText: String {
        switch phase {
        case .scanning:
            return "正在查找同一网络下的电视…"
        case .empty:
            return "没找到电视。请确认电视已打开「手机推送」并与手机在同一网络。"
        }
    }

    private func rescan() {
        phase = .scanning
        // 设备发现依赖后端 /api/app/v1/devices 的注册与配对流程，
        // 当前版本只做到"扫描中 → 无设备"的完整交互闭环。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            phase = .empty
        }
    }
}
