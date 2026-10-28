import SwiftUI

/// 设置：配置地址、数据源列表、缓存与数据管理。
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var configInput = ""
    @State private var showResetConfirm = false
    @State private var showClearHistoryConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                configSection
                sourceSection
                storageSection
                aboutSection
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .pageBackground()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configInput = app.configURL
        }
        .alert("更换配置后需要重新加载", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                app.reset()
                dismiss()
            }
        } message: {
            Text("当前的收藏和历史记录会保留。")
        }
        .alert("清空观看历史？", isPresented: $showClearHistoryConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                library.clearHistory()
            }
        }
    }

    // MARK: - 配置

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("配置")

            VStack(alignment: .leading, spacing: 10) {
                TextField("配置地址", text: $configInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                HStack(spacing: 10) {
                    Button {
                        Task { await app.loadConfig(configInput) }
                    } label: {
                        HStack(spacing: 6) {
                            if app.isLoading {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            }
                            Text(app.isLoading ? "加载中…" : "重新加载")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        showResetConfirm = true
                    } label: {
                        Text("更换")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 76, height: 40)
                            .background(Capsule().fill(Theme.panelHigh))
                    }
                    .buttonStyle(PressScaleStyle())
                }

                if let error = app.errorText {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(14)
            .panel(radius: 16)
        }
    }

    // MARK: - 数据源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("数据源（\(app.sources.count)）")

            VStack(spacing: 0) {
                ForEach(Array(app.sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        app.selectSource(source)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(app.currentSource?.key == source.key ? Theme.accent : Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)

                            Text(source.name)
                                .font(.system(size: 13))
                                .foregroundStyle(source.isSupported ? Theme.textSecondary : Theme.textTertiary)
                                .lineLimit(1)

                            Spacer()

                            Text(source.isSupported ? source.typeLabel : "\(source.typeLabel) 不支持")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    .disabled(!source.isSupported)

                    if index < app.sources.count - 1 {
                        Divider().background(Theme.divider)
                    }
                }
            }
            .padding(.horizontal, 14)
            .panel(radius: 16)
        }
    }

    // MARK: - 存储

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("数据")

            VStack(spacing: 0) {
                actionRow(icon: "photo.on.rectangle", title: "清除图片缓存") {
                    ImagePipeline.shared.clear()
                    Haptics.success()
                }

                Divider().background(Theme.divider)

                actionRow(icon: "clock.arrow.circlepath", title: "清空观看历史") {
                    showClearHistoryConfirm = true
                }

                Divider().background(Theme.divider)

                actionRow(icon: "heart.slash", title: "清空收藏（\(library.favorites.count)）") {
                    for video in library.favorites {
                        library.removeFavorite(video)
                    }
                    Haptics.success()
                }
            }
            .padding(.horizontal, 14)
            .panel(radius: 16)
        }
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("关于")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("云影视")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Text("本应用不提供、不内置任何影视资源。所有内容均来自使用者自行导入的第三方接口，相关内容的合法性与版权责任由使用者自行承担。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(radius: 16)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 2)
    }
}
