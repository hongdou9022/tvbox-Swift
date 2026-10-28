import SwiftUI

/// 海报卡片：2:3 比例，右下角压一行备注。
struct PosterCard: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            poster
            titleBlock
        }
    }

    private var poster: some View {
        // Color.clear + aspectRatio 是撑出固定比例最稳的写法，
        // 直接用 ZStack 会因为图片没有固有尺寸导致高度塌陷。
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                RemoteImage(urlString: video.pic, contentMode: .fill)
            }
            .overlay(alignment: .bottomLeading) {
                if !video.note.isEmpty {
                    ZStack(alignment: .bottomLeading) {
                        Theme.posterScrim

                        Text(video.note)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                            )
                            .padding(6)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .cardShadow()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(video.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(video.subtitleLine.isEmpty ? " " : video.subtitleLine)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }
}

/// 首页顶部推荐位卡片（大图 + 信息 + 播放按钮）。
struct HeroCard: View {
    let video: Video

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景用海报放大 + 模糊，避免 2:3 图硬拉成 16:9
            RemoteImage(urlString: video.pic, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipped()
                .blur(radius: 18, opaque: true)
                .overlay(Color.black.opacity(0.35))

            LinearGradient(
                colors: [Color.black.opacity(0.1), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 12) {
                RemoteImage(urlString: video.pic, contentMode: .fill, cornerRadius: 10)
                    .frame(width: 76, height: 114)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(video.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if !video.note.isEmpty {
                        Text(video.note)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
                    }

                    if !video.subtitleLine.isEmpty {
                        Text(video.subtitleLine)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("立即观看")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accentGradient, in: Capsule())
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
