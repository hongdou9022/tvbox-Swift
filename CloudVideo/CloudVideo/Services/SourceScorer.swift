import Foundation

/// 源动态评分（SEARCH_OPTIMIZATION 2.9）。
///
/// 思路：每次搜索都记录各源的真实表现，长期用下来稳定快速的源自然排到前面。
/// 评分持久化在本地，重启后继续生效。
@MainActor
final class SourceScorer {

    static let shared = SourceScorer()

    /// 冷启动阈值：样本不足时向默认分 50 收敛，避免一两次偶然结果决定排序。
    static let minSamples = 3
    static let defaultScore = 50.0

    struct Record: Codable {
        var score: Double = SourceScorer.defaultScore
        var samples: Int = 0
        var successes: Int = 0
        var failures: Int = 0
        /// 最近一次成功的耗时（毫秒），未采样为 0。
        var lastLatencyMs: Int = 0

        var successRate: Double {
            samples == 0 ? 0 : Double(successes) / Double(samples)
        }

        var isSampled: Bool { samples > 0 }

        /// 冷启动收敛后的有效分。
        var effectiveScore: Double {
            guard samples < SourceScorer.minSamples else { return score }
            let c = Double(samples) / Double(SourceScorer.minSamples)
            return SourceScorer.defaultScore * (1 - c) + score * c
        }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "cloudvideo.search.sourceScore"
    private var records: [String: Record] = [:]

    private init() {
        load()
    }

    // MARK: - 查询

    func record(for id: String) -> Record {
        records[id] ?? Record()
    }

    /// 排序用的分数，越大越靠前。
    func score(for id: String) -> Double {
        record(for: id).effectiveScore
    }

    /// 设置页「搜索源评分」列表：按分数降序。
    func ranking() -> [(id: String, record: Record)] {
        records
            .map { (id: $0.key, record: $0.value) }
            .sorted { lhs, rhs in
                if lhs.record.effectiveScore != rhs.record.effectiveScore {
                    return lhs.record.effectiveScore > rhs.record.effectiveScore
                }
                return lhs.id < rhs.id
            }
    }

    // MARK: - 记录

    /// 成功：延迟与结果数共同决定样本分，再按 0.15 指数衰减并入总分。
    func recordSuccess(id: String, latencyMs: Int, resultCount: Int) {
        var record = records[id] ?? Record()

        let latencyScore = Self.latencyScore(ms: latencyMs)
        // 快但没结果的源不该拿满分
        let outcomeScore = resultCount > 0 ? 100.0 : 60.0
        let sample = latencyScore * 0.55 + outcomeScore * 0.45
        record.score = record.score * 0.85 + sample * 0.15

        record.samples += 1
        record.successes += 1
        record.lastLatencyMs = latencyMs

        records[id] = record
        persist()
    }

    /// 失败：直接按 0 分参与衰减。失败扣分重于成功加分。
    func recordFailure(id: String) {
        var record = records[id] ?? Record()
        record.score = record.score * 0.85
        record.samples += 1
        record.failures += 1
        records[id] = record
        persist()
    }

    func reset() {
        records.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    /// 300ms→100 分，8s→0 分，中间按对数过渡。
    static func latencyScore(ms: Int) -> Double {
        let latency = max(Double(ms), 1)
        let fast = log(300.0)
        let slow = log(8000.0)
        let ratio = (log(latency) - fast) / (slow - fast)
        return min(max(100 * (1 - ratio), 0), 100)
    }

    // MARK: - 持久化

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return
        }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
