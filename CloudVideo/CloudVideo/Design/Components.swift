import SwiftUI

// MARK: - 分区标题

/// 规范 3.2-3：左侧 3×16dp 绿色竖条 + 8dp 间距 + 17sp 粗体标题。
struct SectionTitleBar: View {
    let title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 3, height: 16)

            Text(title)
                .font(Theme.fontSection)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 8)

            if let trailing {
                Button {
                    trailingAction?()
                } label: {
                    HStack(spacing: 2) {
                        Text(trailing)
                            .font(Theme.font(11))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textWeak)
                }
                .buttonStyle(.plain)
                .disabled(trailingAction == nil)
            }
        }
    }
}

// MARK: - 按钮

/// 绿色主按钮（登录页「连接」）。
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, .bold))
            .foregroundStyle(Color(hex: 0x08150E))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                    .fill(enabled ? Theme.accent : Theme.accent.opacity(0.45))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 胶囊标签（频道、来源、清晰度等）。
struct ChipView: View {
    let title: String
    var selected: Bool = false
    var accentColor: Color = Theme.accent
    var font: Font = Theme.font(13)

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(selected ? accentColor : Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? accentColor.opacity(0.14) : Theme.card)
            )
    }
}

/// 只保留点击反馈，不改变视觉。
struct TapScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - 空态 / 加载

/// 规范 8：分类加载中「加载中…」、到底「没有更多了」、分类空「暂无内容」。
struct ListFooterView: View {
    enum State {
        case loading
        case noMore
        case empty
    }

    let state: State

    var body: some View {
        Text(text)
            .font(Theme.font(12))
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }

    private var text: String {
        switch state {
        case .loading: return "加载中…"
        case .noMore: return "没有更多了"
        case .empty: return "暂无内容"
        }
    }
}

struct EmptyHintView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(text)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textWeak)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 圆形图标按钮

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 38
    var tint: Color = Theme.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(TapScaleStyle(scale: 0.9))
    }
}

// MARK: - 弹层拖拽条

/// 规范 5.5-1：36×4dp 居中拖拽条。
struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }
}
