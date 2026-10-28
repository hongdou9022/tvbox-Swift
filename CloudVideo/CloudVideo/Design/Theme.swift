import SwiftUI
import UIKit

/// 云影视设计系统：深空底色 + 蓝紫渐变，整体走"影院暗场"质感。
enum Theme {

    // MARK: - 底色

    /// 页面最底层背景
    static let bg = Color(hex: 0x06070B)
    /// 次级背景（Tab 栏、分组条）
    static let bgRaised = Color(hex: 0x0C0F18)
    /// 卡片面板
    static let panel = Color(hex: 0x141826)
    /// 高亮面板 / 未选中标签
    static let panelHigh = Color(hex: 0x1D2334)
    /// 分隔线
    static let divider = Color.white.opacity(0.07)

    // MARK: - 文字

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.36)

    // MARK: - 品牌色

    static let accent = Color(hex: 0x4C8DFF)
    static let accent2 = Color(hex: 0x9B6BFF)
    static let gold = Color(hex: 0xF7C25C)
    static let danger = Color(hex: 0xFF5D67)

    // MARK: - 渐变

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x4C8DFF), Color(hex: 0x9B6BFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let pageGradient = LinearGradient(
        colors: [Color(hex: 0x0B0F1A), Color(hex: 0x05060A)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 海报底部用于压住文字的黑渐变
    static let posterScrim = LinearGradient(
        colors: [Color.black.opacity(0.75), Color.black.opacity(0.0)],
        startPoint: .bottom,
        endPoint: .center
    )

    // MARK: - 尺寸

    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 20
    static let pagePadding: CGFloat = 16
}

extension Color {
    /// 用 0xRRGGBB 形式的整数构造颜色，避免到处写浮点。
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension View {
    /// 统一的页面背景（含安全区）。
    func pageBackground() -> some View {
        background(Theme.pageGradient.ignoresSafeArea())
    }

    /// 给普通视图加一点"卡片悬浮"的投影。
    func cardShadow() -> some View {
        shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 6)
    }
}

/// 轻量触觉反馈。
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
