import SwiftUI

/// 设置 → 播放与搜索 →「搜索源评分」（SEARCH_OPTIMIZATION 2.9）。
///
/// 按分数降序展示每个源的：源名（爬虫标「·源」）、分数、样本数、成功率、最近延迟。
/// 未采样源显示默认 50.0 与「—」。底部可清除记录，用于重新积累样本。
struct SourceScoreSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []
    @State private var showResetConfirm = false

    struct Row: Identifiable {
        let id: String
        let name: String
        let isSpider: Bool
        let score: Double
        let samples: Int
        let successRate: Double
        let latencyMs: Int

        var sampled: Bool { samples > 0 }

        /// 分数配色：≥55 绿色、40~55 常规、<40 橙色，未采样灰色。
        var scoreColor: Color {
            guard sampled else { return Theme.textFaint }
            if score >= 55 { return Theme.accent }
            if score >= 40 { return Theme.textSecondary }
            return Theme.playAccent
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            HStack {
                Text("搜索源评分")
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textWeak)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.padSheet)
            .padding(.bottom, 8)

            Text("每次搜索都会记录各源的真实表现，稳定快速的源会自然排到前面。")
                .font(Theme.font(11))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.padSheet)
                .padding(.bottom, 10)

            if rows.isEmpty {
                EmptyHintView(icon: "chart.bar", text: "还没有搜索记录")
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                    .padding(.horizontal, Theme.padSheet)
                }
            }

            Button {
                showResetConfirm = true
            } label: {
                Text("清除评分记录")
                    .font(Theme.font(13))
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                            .fill(Theme.cardDeep)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.padSheet)
            .padding(.vertical, 12)
        }
        .detailBackground()
        .onAppear(perform: reload)
        .phoneConfirm(
            isPresented: $showResetConfirm,
            title: "清除评分记录？",
            message: "清除后所有源回到默认分 50，需要重新积累样本。",
            confirmTitle: "清除"
        ) {
            SourceScorer.shared.reset()
            reload()
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(Theme.font(13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if row.isSpider {
                Text("·源")
                    .font(Theme.font(10))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer(minLength: 6)

            Text(row.sampled ? String(format: "%.1f", row.score) : "50.0")
                .font(Theme.font(13, .bold))
                .foregroundStyle(row.scoreColor)
                .frame(width: 40, alignment: .trailing)

            Text(row.sampled ? "\(row.samples) 次" : "—")
                .font(Theme.font(10))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 40, alignment: .trailing)

            Text(row.sampled ? String(format: "%.0f%%", row.successRate * 100) : "—")
                .font(Theme.font(10))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 36, alignment: .trailing)

            Text(row.sampled && row.latencyMs > 0 ? "\(row.latencyMs)ms" : "—")
                .font(Theme.font(10))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 11)
    }

    private func reload() {
        let store = LocalSourceStore.shared
        var nameMap: [String: (String, Bool)] = [:]
        for site in store.sites { nameMap[site.id] = (site.name, false) }
        for spider in store.spiders { nameMap[spider.id] = (spider.name, true) }

        // 未采样的源也列出来，方便对照默认分
        var ids = Set(SourceScorer.shared.ranking().map { $0.id })
        for id in nameMap.keys { ids.insert(id) }

        rows = ids.compactMap { id in
            let record = SourceScorer.shared.record(for: id)
            guard let meta = nameMap[id] else {
                // 源已从配置里移除，但仍保留评分记录
                guard record.isSampled else { return nil }
                return Row(
                    id: id,
                    name: id,
                    isSpider: false,
                    score: record.effectiveScore,
                    samples: record.samples,
                    successRate: record.successRate,
                    latencyMs: record.lastLatencyMs
                )
            }
            return Row(
                id: id,
                name: meta.0,
                isSpider: meta.1,
                score: record.effectiveScore,
                samples: record.samples,
                successRate: record.successRate,
                latencyMs: record.lastLatencyMs
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.01 { return lhs.score > rhs.score }
            return lhs.name < rhs.name
        }
    }
}
