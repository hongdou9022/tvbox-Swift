import SwiftUI

/// 规范 0.5（v1.6）：**禁止使用系统原生弹窗**。
///
/// 系统弹窗灰底直角、按钮同色，与应用深色圆角风格割裂。
/// 这里提供两个等价实现：
/// - `phoneConfirm`：居中确认卡片
/// - `PhoneDropdown`：贴锚点下方的下拉菜单
///
/// 配色与尺寸严格按规范：卡片 `#1C1E24` 底、14dp 圆角、1dp `#2A2C33` 描边；
/// 确认弹窗左右留白 36dp、遮罩 0.55；下拉菜单每项 42dp、遮罩 0.35。

// MARK: - 确认弹窗

private struct PhoneConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let confirmTitle: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { dismiss() }

                    VStack(spacing: 0) {
                        Text(title)
                            .font(Theme.font(16, .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 22)
                            .padding(.horizontal, 20)

                        if let message, !message.isEmpty {
                            Text(message)
                                .font(Theme.font(13))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.top, 20)

                        HStack(spacing: 0) {
                            Button {
                                dismiss()
                            } label: {
                                Text("取消")
                                    .font(Theme.font(14))
                                    .foregroundStyle(Color(hex: 0x8A8F9C))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 1, height: 24)

                            Button {
                                dismiss()
                                onConfirm()
                            } label: {
                                Text(confirmTitle)
                                    .font(Theme.font(14, .bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: 0x1C1E24))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: 0x2A2C33), lineWidth: 1)
                    )
                    .padding(.horizontal, 36)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }

    private func dismiss() {
        isPresented = false
    }
}

extension View {
    /// 应用风格确认弹窗（替代系统 `alert` / `confirmationDialog`）。
    func phoneConfirm(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        confirmTitle: String = "确认",
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            PhoneConfirmModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                onConfirm: onConfirm
            )
        )
    }
}

// MARK: - 下拉菜单

struct PhoneDropdownOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    /// 首项「全站」没有角标。
    let badge: String?

    init(id: String, title: String, subtitle: String? = nil, badge: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
    }
}

/// 贴锚点下方的下拉浮层（规范 0.5）：不是居中对话框。
///
/// - 宽度 `max(180, 锚点宽)`，上限 240dp，且不超出屏幕
/// - 贴锚点下方 4dp；底部空间不足时限高并可滚动
/// - 每项 42dp，13sp；选中绿字 + `#24262D` 略亮底
struct PhoneDropdown: View {
    let anchor: CGRect
    let options: [PhoneDropdownOption]
    let selectedId: String
    let onSelect: (PhoneDropdownOption) -> Void
    let onDismiss: () -> Void

    private let minWidth: CGFloat = 180
    private let maxWidth: CGFloat = 240
    private let rowHeight: CGFloat = 42
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            // 锚点是全局坐标，这里换算成浮层自身的局部坐标
            let origin = geo.frame(in: .global).origin
            let local = CGRect(
                x: anchor.minX - origin.x,
                y: anchor.minY - origin.y,
                width: anchor.width,
                height: anchor.height
            )

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                menuCard(local: local, screen: geo.size)
                    .offset(x: originX(local, screen: geo.size), y: originY(local, screen: geo.size))
            }
        }
    }

    private func menuCard(local: CGRect, screen: CGSize) -> some View {
        let width = min(max(local.width, minWidth), maxWidth)
        let contentHeight = CGFloat(options.count) * rowHeight + 8
        let available = max(screen.height - originY(local, screen: screen) - 24, rowHeight * 2)
        let height = min(contentHeight, available)

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.title)
                                .font(Theme.font(13))
                                .foregroundStyle(option.id == selectedId ? Theme.accent : Theme.textSecondary)
                                .lineLimit(1)

                            if let badge = option.badge, !badge.isEmpty {
                                Text(badge)
                                    .font(Theme.font(10))
                                    .foregroundStyle(option.id == selectedId ? Theme.accent.opacity(0.8) : Theme.textFaint)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            option.id == selectedId
                                ? Color(hex: 0x24262D)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0x1C1E24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0x2A2C33), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    private func originX(_ local: CGRect, screen: CGSize) -> CGFloat {
        let width = min(max(local.width, minWidth), maxWidth)
        return min(max(local.minX, 8), max(screen.width - width - 8, 8))
    }

    private func originY(_ local: CGRect, screen: CGSize) -> CGFloat {
        min(local.maxY + gap, max(screen.height - rowHeight * 2 - 24, 8))
    }
}

// MARK: - 锚点

/// 记录触发控件在屏幕坐标系里的位置，供下拉菜单定位。
struct DropdownAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

extension View {
    /// 把当前视图登记为下拉菜单的锚点。
    ///
    /// 同一页面只有一个锚点时用这个；多个锚点请用 `AnchoredRow`，
    /// 否则 PreferenceKey 只会保留最后一个非零值。
    func dropdownAnchor() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: DropdownAnchorKey.self, value: geo.frame(in: .global))
            }
        )
    }
}

/// 自带位置记录的可点击行，点击时把自身全局坐标回传。
struct AnchoredRow<Content: View>: View {
    let action: (CGRect) -> Void
    let content: Content

    @State private var frame: CGRect = .zero

    init(action: @escaping (CGRect) -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button {
            action(frame)
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newValue in
                        frame = newValue
                    }
            }
        )
    }
}
