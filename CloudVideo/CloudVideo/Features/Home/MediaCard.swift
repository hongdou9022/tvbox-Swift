import SwiftUI

// MARK: - 推荐卡片（规范 3.4）

/// 3 列横版卡片：图高 86dp，左上类型角标，右上金色评分。
struct MediaCard: View {
    let title: String
    let poster: String
    let badge: String
    let rating: Double?
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            posterBox
            Text(title)
                .font(Theme.fontCardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(meta.isEmpty ? " " : meta)
                .font(Theme.fontCardMeta)
                .foregroundStyle(Theme.textWeak)
                .lineLimit(1)
        }
    }

    private var posterBox: some View {
        Color.clear
            .frame(height: 86)
            .overlay {
                RemoteImage(urlString: poster, contentMode: .fill, cornerRadius: Theme.radiusCard)
            }
            .overlay(alignment: .topLeading) {
                if !badge.isEmpty {
                    Text(badge)
                        .font(Theme.fontBadge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        )
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let rating, rating > 0 {
                    Text(String(format: "★%.1f", rating))
                        .font(Theme.fontBadge)
                        .foregroundStyle(Color(hex: 0xF5C24A))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        )
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
}

// MARK: - 横幅轮播（规范 3.2-1）

/// 16:9 圆角大图，高 196dp，底部居中白色分页圆点，4 秒自动轮播。
struct BannerCarousel: View {
    let items: [RecommendItem]
    let onTap: (RecommendItem) -> Void

    @State private var index = 0
    @State private var autoTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    bannerPage(item)
                        .tag(offset)
                        .onTapGesture { onTap(item) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 196)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { dot in
                        Circle()
                            .fill(dot == index ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .onAppear { startAutoScroll() }
        .onDisappear { autoTask?.cancel() }
        .onChange(of: items.count) { _, _ in startAutoScroll() }
    }

    private func bannerPage(_ item: RecommendItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(urlString: item.poster ?? "", contentMode: .fill, cornerRadius: 0)

            // 底部渐变遮罩，保证标题可读
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(Theme.font(17, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.font(11))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .topLeading) {
            if let type = item.type, !type.isEmpty {
                Text(type)
                    .font(Theme.fontBadge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    /// 规范 3.2-1：4 秒自动轮播，仅 1 张时不轮播。
    private func startAutoScroll() {
        autoTask?.cancel()
        guard items.count > 1 else { return }

        autoTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, items.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    index = (index + 1) % items.count
                }
            }
        }
    }
}
