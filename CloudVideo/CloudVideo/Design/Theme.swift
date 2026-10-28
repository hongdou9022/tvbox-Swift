import SwiftUI
import UIKit

/// 设计系统 —— 严格对齐 `Box/docs/PHONE_UI_SPEC.md` 第 0 章。
///
/// 尺寸单位为 dp，iOS 按 pt 1:1 使用（见规范 9.1）。
enum Theme {

    // MARK: - 0.1 配色

    /// 详情 / 播放页底色
    static let bgDetail = Color(hex: 0x151823)
    /// 首页 / 搜索 / 我的底色
    static let bgHome = Color(hex: 0x0E0F13)
    /// 主题强调色：选中态、来源名、集数徽标文字
    static let accent = Color(hex: 0x2BD576)
    /// 播放器进度强调：进度条、当前集、已收藏
    static let playAccent = Color(hex: 0xFF7800)

    static let textPrimary = Color.white
    /// 元信息、辅助说明
    static let textSecondary = Color(hex: 0x9AA0AB)
    /// 提示
    static let textWeak = Color(hex: 0x7D8291)
    /// 页脚
    static let textFaint = Color(hex: 0x5F6470)

    /// 未选中卡片 / 按钮
    static let card = Color(hex: 0x2C303C)
    /// 输入框、海报占位
    static let cardDeep = Color(hex: 0x1A1B22)
    /// 输入框描边
    static let inputBorder = Color(hex: 0x2A2C33)

    /// 弹幕开关打开态
    static let danmakuOn = Color(hex: 0x6BE38F)
    /// 弹幕开关关闭态
    static let danmakuOff = Color(hex: 0x8A8FA3)

    // MARK: - 0.3 圆角与间距

    static let radiusCard: CGFloat = 10
    static let radiusEpisode: CGFloat = 8
    static let radiusInput: CGFloat = 18
    static let radiusSheet: CGFloat = 20

    /// 首页 / 详情左右内边距
    static let padPage: CGFloat = 14
    /// 列表网格
    static let padGrid: CGFloat = 9
    /// 弹层
    static let padSheet: CGFloat = 20
    /// 分区之间垂直间距
    static let sectionGap: CGFloat = 19

    // MARK: - 0.2 字号

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// 影片标题（详情页）
    static let fontTitle = font(20, .bold)
    /// 分区标题
    static let fontSection = font(17, .bold)
    /// 卡片标题
    static let fontCardTitle = font(13, .bold)
    /// 卡片元信息
    static let fontCardMeta = font(10)
    /// 徽标 / 角标
    static let fontBadge = font(9)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension View {
    /// 首页 / 搜索 / 我的
    func homeBackground() -> some View {
        background(Theme.bgHome.ignoresSafeArea())
    }

    /// 详情 / 播放页
    func detailBackground() -> some View {
        background(Theme.bgDetail.ignoresSafeArea())
    }
}

// MARK: - 屏幕方向

/// 详情/播放页固定竖屏，仅全屏时允许横屏（规范 9.2）。
enum OrientationLock {
    /// 当前允许的方向，由 AppDelegate 读取。
    static var mask: UIInterfaceOrientationMask = .portrait

    /// 切到竖屏。
    static func portrait() {
        apply(.portrait)
    }

    /// 切到横屏（用于全屏播放）。
    static func landscape() {
        apply(.landscapeRight)
    }

    private static func apply(_ target: UIInterfaceOrientationMask) {
        mask = target
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target))
        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
