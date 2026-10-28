import Foundation

/// 数据源站点。对应 TVBox 配置里的 `sites[]`。
struct SourceBean: Identifiable, Hashable, Codable {
    var key: String
    var name: String
    var api: String
    /// 0 = XML，1 = JSON，3 = JAR(Spider)，4 = Remote
    var type: Int
    var searchable: Bool
    var filterable: Bool
    var ext: String?

    var id: String { key }

    /// iOS 端能直接跑的类型（type=3 依赖 Java 运行时，无法支持）。
    var isSupported: Bool {
        type == 0 || type == 1 || type == 4
    }

    var typeLabel: String {
        switch type {
        case 0: return "XML"
        case 1: return "JSON"
        case 3: return "JAR"
        case 4: return "Remote"
        default: return "未知"
        }
    }

    var isHTTP: Bool {
        api.hasPrefix("http://") || api.hasPrefix("https://")
    }
}

/// 直播条目（来自配置的 `lives[]`，可能是一个 m3u/txt 地址）。
struct LiveEntry: Identifiable, Hashable, Codable {
    var name: String
    var url: String
    var group: String

    var id: String { name + "|" + url }
}
