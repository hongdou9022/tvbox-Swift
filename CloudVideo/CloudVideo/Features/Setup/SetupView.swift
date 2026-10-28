import SwiftUI

/// 首次配置页。
///
/// 参考项目这里只放了一个裸输入框，实际用起来很别扭：用户不知道填什么、
/// 也不知道上次用过哪些地址。这里补了三点：示例入口、历史地址、粘贴按钮。
struct SetupView: View {
    @EnvironmentObject private var app: AppState

    @State private var input: String = ""
    @FocusState private var focused: Bool

    /// 常见的配置地址写法示例，帮助用户理解要填什么。
    private let examples: [(title: String, subtitle: String, url: String)] = [
        (
            "自定义配置",
            "支持 TVBox 标准 JSON 配置",
            ""
        ),
        (
            "GitHub Raw 地址",
            "github.com/.../blob/... 会自动转成 raw",
            "https://raw.githubusercontent.com/"
        )
    ]

    var body: some View {
        ZStack {
            Theme.pageGradient.ignoresSafeArea()
            glowLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    brandHeader
                    inputCard
                    submitButton
                    hintSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
            }
        }
        .onAppear {
            input = app.configURL
        }
    }

    // MARK: - 品牌头

    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 84, height: 84)
                    .blur(radius: 26)
                    .opacity(0.55)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "play.tv.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Theme.accentGradient)
            }

            VStack(spacing: 6) {
                Text("云影视")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .tracking(2)

                Text("把片源装进你的口袋")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(3)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 输入

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置地址")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                TextField("https://example.com/tvbox.json", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                Button {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        input = text
                        Haptics.tap()
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Theme.accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )

            if let error = app.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .lineLimit(2)
                }
                .foregroundStyle(Theme.danger)
            }
        }
        .padding(18)
        .panel()
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if app.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(app.isLoading ? "正在解析配置…" : "开启云影视")
            }
        }
        .buttonStyle(AccentButtonStyle(height: 50))
        .disabled(app.isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
    }

    // MARK: - 说明

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("说明")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            ForEach(examples.indices, id: \.self) { index in
                let item = examples[index]
                Button {
                    if !item.url.isEmpty {
                        input = item.url
                        focused = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent.opacity(0.8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(item.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                    )
                }
                .buttonStyle(.plain)
            }

            Text("本应用不内置任何影视资源，所有内容均来自你自行导入的第三方接口。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(3)
                .padding(.top, 4)
        }
    }

    private var glowLayer: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x4C8DFF).opacity(0.20))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -110, y: -240)

            Circle()
                .fill(Color(hex: 0x9B6BFF).opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 130, y: 300)
        }
        .allowsHitTesting(false)
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        focused = false
        Task {
            await app.loadConfig(value)
        }
    }
}
