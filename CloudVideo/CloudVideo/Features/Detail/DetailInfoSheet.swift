import SwiftUI

/// 详情弹层（规范 5.5）。
struct DetailInfoSheet: View {
    let detail: MediaDetail?
    let fallbackTitle: String
    let fallbackPoster: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetGrabber()
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail?.title ?? fallbackTitle)
                            .font(Theme.font(18, .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let score = detail?.score, !score.isEmpty {
                            Text(score)
                                .font(Theme.font(15, .bold))
                                .foregroundStyle(Theme.playAccent)
                        }

                        if let actors = detail?.actors, !actors.isEmpty {
                            Text(actors)
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(3)
                        }

                        if let detail {
                            Text(metaLine(detail))
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.textWeak)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)

                    // 规范 5.5-3：竖版海报 78×110dp
                    RemoteImage(
                        urlString: detail?.poster ?? fallbackPoster,
                        contentMode: .fill,
                        cornerRadius: 6
                    )
                    .frame(width: 78, height: 110)
                }
                .padding(.horizontal, Theme.padSheet)

                VStack(alignment: .leading, spacing: 8) {
                    Text("概要")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(summary)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(5)
                }
                .padding(.horizontal, Theme.padSheet)
                .padding(.top, 20)

                if let name = detail?.libraryName, !name.isEmpty {
                    Text("来源：\(name)")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, Theme.padSheet)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                }
            }
        }
        .background(Theme.bgDetail)
    }

    private var summary: String {
        guard let detail, !detail.plainContent.isEmpty else { return "暂无简介" }
        return detail.plainContent
    }

    private func metaLine(_ detail: MediaDetail) -> String {
        var parts: [String] = []
        if let year = detail.year, !year.isEmpty { parts.append(year) }
        if let area = detail.area, !area.isEmpty { parts.append(area) }
        if let director = detail.director, !director.isEmpty {
            parts.append("导演:\(director)")
        }
        return parts.joined(separator: "  ")
    }
}
