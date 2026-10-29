import Foundation

/// 搜索结果缓存（SEARCH_OPTIMIZATION 2.5）。
///
/// TTL 2 分钟、容量 200 条，key = `配置版本 + 关键词 + 页 + 范围`。
/// 配置版本参与 key，后台改源配置后旧缓存自动失效。
@MainActor
final class SearchCache {

    static let shared = SearchCache()

    static let ttl: TimeInterval = 2 * 60
    static let capacity = 200

    private struct Entry {
        let hits: [SearchHit]
        let stats: SearchStats
        let sources: [String]
        let storedAt: Date
    }

    private var storage: [String: Entry] = [:]
    /// 插入顺序，用于超出容量时淘汰最旧的。
    private var order: [String] = []

    private init() {}

    func key(keyword: String, page: Int, scope: SearchScope) -> String {
        let scopeKey: String
        switch scope {
        case .all: scopeKey = "all"
        case .site(let id, _): scopeKey = "site:" + id
        case .spider(let id, _): scopeKey = "spider:" + id
        }
        return [LocalSourceStore.shared.version, scopeKey, "\(page)", keyword].joined(separator: "|")
    }

    func value(for key: String) -> (hits: [SearchHit], stats: SearchStats, sources: [String])? {
        guard let entry = storage[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < Self.ttl else {
            storage.removeValue(forKey: key)
            order.removeAll { $0 == key }
            return nil
        }
        return (entry.hits, entry.stats, entry.sources)
    }

    func store(key: String, hits: [SearchHit], stats: SearchStats, sources: [String]) {
        storage[key] = Entry(hits: hits, stats: stats, sources: sources, storedAt: Date())
        order.removeAll { $0 == key }
        order.append(key)

        while order.count > Self.capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    func clear() {
        storage.removeAll()
        order.removeAll()
    }
}
