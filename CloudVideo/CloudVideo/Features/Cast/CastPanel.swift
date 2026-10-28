import SwiftUI

/// 推送到电视浮窗（规范 5.7）。
///
/// 以底部面板形式浮在当前页，不跳转页面，横屏下也不切走。
struct CastPanel: View {
    let payload: CastPayload

    @Environment(\.dismiss) private var dismiss
    @StateObject private var cast = CastService.shared

    @State private var hint = "正在查找同一网络下的电视…"
    @State private var pushingDeviceId: String?
    @State private var resultMessage: String?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            Text("推送到电视")
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.textPrimary)

            Text(hint)
                .font(Theme.font(12))
                .foregroundStyle(failed ? Theme.playAccent : Theme.textWeak)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.padSheet)
                .padding(.top, 8)

            deviceList

            Button {
                rescan()
            } label: {
                HStack(spacing: 6) {
                    if cast.isScanning {
                        ProgressView()
                            .tint(Theme.accent)
                            .scaleEffect(0.75)
                    }
                    Text(cast.isScanning ? "扫描中…" : "重新扫描")
                }
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
            .disabled(cast.isScanning)
            .padding(.horizontal, Theme.padSheet)
            .padding(.bottom, 26)
        }
        .background(Theme.bgDetail)
        .onAppear { rescan() }
    }

    // MARK: - 设备列表

    @ViewBuilder
    private var deviceList: some View {
        if cast.devices.isEmpty {
            VStack(spacing: 8) {
                if cast.isScanning {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(.top, 26)
                } else {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(cast.devices) { device in
                        deviceRow(device)
                    }
                }
                .padding(.horizontal, Theme.padSheet)
                .padding(.top, 16)
            }
            .frame(maxHeight: 300)
            .padding(.bottom, 14)
        }
    }

    private func deviceRow(_ device: CastDevice) -> some View {
        let paired = cast.isPaired(device)
        let isPushing = pushingDeviceId == device.deviceId

        return Button {
            push(to: device, paired: paired)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)

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

                if isPushing {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.8)
                } else {
                    Text(device.statusText(paired: paired))
                        .font(Theme.font(11))
                        .foregroundStyle(paired ? Theme.accent : Theme.textWeak)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.cardDeep)
            )
        }
        .buttonStyle(.plain)
        .disabled(pushingDeviceId != nil)
    }

    // MARK: - 动作

    private func rescan() {
        failed = false
        resultMessage = nil
        hint = "正在查找同一网络下的电视…"

        Task {
            await cast.scan()
            guard pushingDeviceId == nil else { return }
            if cast.devices.isEmpty {
                hint = "没找到电视。请确认电视已打开「手机推送」并与手机在同一网络。"
            } else {
                hint = "点一下要推送的电视"
            }
        }
    }

    private func push(to device: CastDevice, paired: Bool) {
        guard pushingDeviceId == nil else { return }

        pushingDeviceId = device.deviceId
        failed = false

        // 规范 5.7：未配对时提示到电视上确认
        hint = paired
            ? "正在推送到电视…"
            : "等待电视确认…请在电视上点击「允许」"

        Task {
            do {
                let message = try await cast.push(payload, to: device)
                resultMessage = message
                hint = message
                pushingDeviceId = nil
                // 成功提示后自动收起
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            } catch {
                failed = true
                hint = error.localizedDescription
                pushingDeviceId = nil
            }
        }
    }
}
