import Foundation

/// 单个剧集。
struct Episode: Identifiable, Hashable {
    let name: String
    let url: String

    var id: String { name + "|" + url }
}

/// 一条播放线路（CMS 的 `vod_play_from` + `vod_play_url` 组合）。
struct PlayLine: Identifiable, Hashable {
    let name: String
    var episodes: [Episode]

    var id: String { name }
}

/// 详情页数据。
struct VodDetail: Identifiable, Hashable {
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
    var lines: [PlayLine]

    /// 去掉 HTML 标签后的简介。
    var plainContent: String {
        content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var metaLine: String {
        var parts: [String] = []
        if !year.isEmpty { parts.append(year) }
        if !area.isEmpty { parts.append(area) }
        if !typeName.isEmpty { parts.append(typeName) }
        return parts.joined(separator: " · ")
    }

    /// 从列表条目 + 接口返回的播放字段构造详情。
    static func build(video: Video, playFrom: String, playURL: String) -> VodDetail {
        let flags = playFrom
            .components(separatedBy: "$$$")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let urlGroups = playURL.components(separatedBy: "$$$")

        var lines: [PlayLine] = []
        for (index, group) in urlGroups.enumerated() {
            let episodes = parseEpisodes(group)
            guard !episodes.isEmpty else { continue }

            let flagIndex = index < flags.count ? index : 0
            var lineName = flagIndex < flags.count ? flags[flagIndex] : ""
            if lineName.isEmpty { lineName = "线路\(index + 1)" }

            // 同名线路加序号，避免 Identifiable 冲突
            if lines.contains(where: { $0.name == lineName }) {
                lineName += " (\(index + 1))"
            }
            lines.append(PlayLine(name: lineName, episodes: episodes))
        }

        return VodDetail(
            id: video.id,
            name: video.name,
            pic: video.pic,
            note: video.note,
            year: video.year,
            area: video.area,
            typeName: video.typeName,
            director: video.director,
            actor: video.actor,
            content: video.content,
            lines: lines
        )
    }

    /// 解析 `第1集$http://...#第2集$http://...` 形式的剧集串。
    static func parseEpisodes(_ raw: String) -> [Episode] {
        guard !raw.isEmpty else { return [] }

        var result: [Episode] = []
        let items = raw.components(separatedBy: "#")

        for (index, item) in items.enumerated() {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: "$")
            if parts.count >= 2 {
                let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                // url 里可能还有 $，取剩余部分拼回去
                let url = parts.dropFirst().joined(separator: "$")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else { continue }
                result.append(Episode(name: title.isEmpty ? "第\(index + 1)集" : title, url: url))
            } else if trimmed.hasPrefix("http") {
                result.append(Episode(name: "第\(index + 1)集", url: trimmed))
            }
        }

        return result
    }
}
