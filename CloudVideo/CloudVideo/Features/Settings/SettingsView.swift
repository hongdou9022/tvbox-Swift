import SwiftUI

/// 播放器偏好（规范 7：清晰度偏好、弹幕偏好、播放器解码方式）。
enum PlayerPreferences {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let quality = "cloudvideo.pref.quality"
        static let danmaku = "cloudvideo.pref.danmaku"
        static let decoder = "cloudvideo.pref.decoder"
    }

    static var quality: String {
        get { defaults.string(forKey: Keys.quality) ?? "自动" }
        set { defaults.set(newValue, forKey: Keys.quality) }
    }

    static var danmakuEnabled: Bool {
        get { defaults.object(forKey: Keys.danmaku) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.danmaku) }
    }

    static var decoder: String {
        get { defaults.string(forKey: Keys.decoder) ?? "系统解码" }
        set { defaults.set(newValue, forKey: Keys.decoder) }
    }

    static let qualityOptions = ["自动", "高清", "超清", "蓝光", "2K", "4K"]
    static let decoderOptions = ["系统解码", "硬解优先", "软解优先"]
}

/// 设置页（规范 7）。
///
/// 规范 0.5：不使用系统原生弹窗 —— 断线确认用 `phoneConfirm`，
/// 清晰度 / 解码方式选择用贴锚点的 `PhoneDropdown`。
struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var quality = PlayerPreferences.quality
    @State private var danmaku = PlayerPreferences.danmakuEnabled
    @State private var decoder = PlayerPreferences.decoder

    @State private var showLogoutConfirm = false
    @State private var showScoreSheet = false

    @State private var activeMenu: String?
    @State private var menuAnchor: CGRect = .zero

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                serverSection
                playbackSection
                aboutSection
            }
            .padding(.horizontal, Theme.padPage)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .homeBackground()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let activeMenu {
                PhoneDropdown(
                    anchor: menuAnchor,
                    options: menuOptions(activeMenu),
                    selectedId: activeMenu == "quality" ? quality : decoder,
                    onSelect: { option in
                        if activeMenu == "quality" {
                            quality = option.id
                            PlayerPreferences.quality = option.id
                        } else {
                            decoder = option.id
                            PlayerPreferences.decoder = option.id
                        }
                        self.activeMenu = nil
                    },
                    onDismiss: { self.activeMenu = nil }
                )
            }
        }
        .phoneConfirm(
            isPresented: $showLogoutConfirm,
            title: "断开连接？",
            message: "需要重新输入服务器地址和密码才能连接。",
            confirmTitle: "断开"
        ) {
            session.logout()
        }
        .sheet(isPresented: $showScoreSheet) {
            SourceScoreSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.bgDetail)
        }
    }

    // MARK: - 服务器

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("服务器")

            VStack(spacing: 0) {
                infoRow("名称", session.serverDisplayName)
                Divider().background(Color.white.opacity(0.06))
                infoRow("地址", session.serverAddress)
                Divider().background(Color.white.opacity(0.06))
                infoRow("账号", session.user?.username ?? "—")
                Divider().background(Color.white.opacity(0.06))

                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Text("断开连接")
                            .font(Theme.font(13))
                            .foregroundStyle(Color(hex: 0xFF6B6B))
                        Spacer()
                    }
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.cardDeep)
            )
        }
    }

    // MARK: - 播放与搜索

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("播放与搜索")

            VStack(spacing: 0) {
                AnchoredRow(action: { rect in
                    menuAnchor = rect
                    activeMenu = "quality"
                }) {
                    pickerRow("清晰度偏好", quality)
                }

                Divider().background(Color.white.opacity(0.06))

                HStack {
                    Text("弹幕默认开启")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $danmaku)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .onChange(of: danmaku) { _, value in
                            PlayerPreferences.danmakuEnabled = value
                        }
                }
                .padding(.vertical, 9)

                Divider().background(Color.white.opacity(0.06))

                AnchoredRow(action: { rect in
                    menuAnchor = rect
                    activeMenu = "decoder"
                }) {
                    pickerRow("播放器解码方式", decoder)
                }

                Divider().background(Color.white.opacity(0.06))

                Button {
                    showScoreSheet = true
                } label: {
                    pickerRow("搜索源评分", scoreSummary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.cardDeep)
            )
        }
    }

    private var scoreSummary: String {
        let sampled = SourceScorer.shared.ranking().filter { $0.record.isSampled }
        return sampled.isEmpty ? "未采样" : "\(sampled.count) 个源"
    }

    private func menuOptions(_ kind: String) -> [PhoneDropdownOption] {
        let values = kind == "quality" ? PlayerPreferences.qualityOptions : PlayerPreferences.decoderOptions
        return values.map { PhoneDropdownOption(id: $0, title: $0) }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("关于")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppInfo.displayName)
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(AppInfo.version)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                }

                Text("本应用不提供、不内置任何影视资源，所有内容均来自你自行连接的媒体服务器。")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.cardDeep)
            )
        }
    }

    // MARK: - 组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(12, .semibold))
            .foregroundStyle(Theme.textWeak)
            .padding(.leading, 2)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textWeak)
            Spacer()
            Text(value)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
    }

    private func pickerRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
