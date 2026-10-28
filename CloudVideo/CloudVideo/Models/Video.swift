import Foundation

/// 列表 / 搜索里的一条影视条目。
/// 对应 TVBox 的 `Movie.Video`，字段名沿用 CMS（苹果 CMS / MacCMS）约定。
struct Video: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var pic: String
    var note: String
    var year: String
    var area: String
    var typeName: String
    var director: String
    var actor: String
    var content: String
    /// 该条目来自哪个源，用于详情页回到正确的接口。
    var sourceKey: String

    init(
        id: String = UUID().uuidString,
        name: String = "",
        pic: String = "",
        note: String = "",
        year: String = "",
        area: String = "",
        typeName: String = "",
        director: String = "",
        actor: String = "",
        content: String = "",
        sourceKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.pic = pic
        self.note = note
        self.year = year
        self.area = area
        self.typeName = typeName
        self.director = director
        self.actor = actor
        self.content = content
        self.sourceKey = sourceKey
    }

    /// 把接口返回的一条 JSON 字典转成模型。
    /// CMS 接口里 `vod_id` / `type_id` 有时是 Int 有时是 String，统一转字符串。
    static func from(dict: [String: Any], sourceKey: String) -> Video {
        Video(
            id: JSONValue.string(dict, "vod_id"),
            name: JSONValue.string(dict, "vod_name"),
            pic: JSONValue.string(dict, "vod_pic"),
            note: JSONValue.string(dict, "vod_remarks"),
            year: JSONValue.string(dict, "vod_year"),
            area: JSONValue.string(dict, "vod_area"),
            typeName: JSONValue.string(dict, "type_name"),
            director: JSONValue.string(dict, "vod_director"),
            actor: JSONValue.string(dict, "vod_actor"),
            content: JSONValue.string(dict, "vod_content"),
            sourceKey: sourceKey
        )
    }

    /// 供 UI 展示的一行副标题。
    var subtitleLine: String {
        var parts: [String] = []
        if !year.isEmpty { parts.append(year) }
        if !area.isEmpty { parts.append(area) }
        if !typeName.isEmpty { parts.append(typeName) }
        return parts.joined(separator: " · ")
    }

    /// 是否看起来像一部剧集（用于详情页剧集区标题）。
    var looksLikeSeries: Bool {
        note.contains("集") || note.contains("更新") || typeName.contains("剧")
    }
}

/// 首页分类。
struct VideoCategory: Identifiable, Hashable {
    let id: String
    let name: String

    /// 内置的"推荐"分类，使用接口 `ac=class` 返回的 list 数据。
    static let featured = VideoCategory(id: "__featured__", name: "推荐")
}

/// 一页列表数据。
struct VideoPage {
    var videos: [Video]
    var pageCount: Int
}

// MARK: - JSON 取值辅助

enum JSONValue {
    /// 按顺序尝试多个 key，返回第一个非空字符串。
    static func string(_ dict: [String: Any], _ keys: String...) -> String {
        for key in keys {
            guard let raw = dict[key] else { continue }
            if raw is NSNull { continue }
            if let s = raw as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let n = raw as? NSNumber {
                return n.stringValue
            }
        }
        return ""
    }

    static func int(_ dict: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            guard let raw = dict[key], !(raw is NSNull) else { continue }
            if let i = raw as? Int { return i }
            if let n = raw as? NSNumber { return n.intValue }
            if let s = raw as? String, let i = Int(s) { return i }
        }
        return nil
    }

    static func array(_ dict: [String: Any], _ keys: String...) -> [[String: Any]]? {
        for key in keys {
            if let arr = dict[key] as? [[String: Any]] { return arr }
        }
        return nil
    }
}
