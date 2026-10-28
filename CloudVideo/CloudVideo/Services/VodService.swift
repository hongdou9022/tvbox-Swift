import Foundation

enum VodError: LocalizedError {
    case unsupported(String)
    case emptyApi
    case badURL(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .unsupported(let type): return "暂不支持 \(type) 类型的数据源"
        case .emptyApi: return "数据源接口地址为空"
        case .badURL(let url): return "接口地址不合法：\(url)"
        case .parseFailed: return "数据解析失败"
        }
    }
}

/// 影视数据服务：把不同源类型的接口统一成同一组方法。
///
/// 支持 type=0（XML）与 type=1/4（JSON）。type=3（JAR/Spider）依赖 Java 运行时，
/// iOS 上无法实现，统一在入口处拦截并给出提示。
final class VodService {
    static let shared = VodService()

    private let net = NetworkClient.shared

    private init() {}

    // MARK: - 首页

    /// 拉取首页分类 + 推荐位。
    func home(for source: SourceBean) async throws -> (categories: [VideoCategory], featured: [Video]) {
        try validate(source)

        let url: String
        if source.type == 0 {
            url = source.api
        } else {
            url = try buildURL(source.api, ["ac": "class"])
        }
        let text = try await net.getString(url)

        if source.type == 0 {
            let categories = parseXMLCategories(text)
            return (categories, [])
        }

        var categories: [VideoCategory] = []
        var featured: [Video] = []

        if let root = jsonRoot(text) {
            if let classList = root["class"] as? [[String: Any]] {
                for item in classList {
                    let id = JSONValue.string(item, "type_id")
                    let name = JSONValue.string(item, "type_name")
                    guard !id.isEmpty, !name.isEmpty else { continue }
                    categories.append(VideoCategory(id: id, name: name))
                }
            }

            if let list = root["list"] as? [[String: Any]] {
                featured = list.compactMap { dict -> Video? in
                    let video = Video.from(dict: dict, sourceKey: source.key)
                    return video.name.isEmpty ? nil : video
                }
            }
        }

        // 部分接口 ac=class 不带 list，退化成拉第一页
        if featured.isEmpty, let first = categories.first {
            let page = try? await videos(for: source, category: first, page: 1)
            featured = Array((page?.videos ?? []).prefix(12))
        }

        return (categories, featured)
    }

    // MARK: - 分类列表

    func videos(for source: SourceBean, category: VideoCategory, page: Int) async throws -> VideoPage {
        try validate(source)

        // type=0 与 type=1/4 的分类列表参数一致，只有返回格式不同
        let url = try buildURL(source.api, ["ac": "videolist", "t": category.id, "pg": "\(page)"])
        let text = try await net.getString(url)

        if source.type == 0 {
            return VideoPage(videos: parseXMLVideos(text, sourceKey: source.key), pageCount: 1)
        }

        guard let root = jsonRoot(text), let list = root["list"] as? [[String: Any]] else {
            return VideoPage(videos: [], pageCount: 1)
        }

        let videos = list.compactMap { dict -> Video? in
            let video = Video.from(dict: dict, sourceKey: source.key)
            return video.name.isEmpty ? nil : video
        }
        let pageCount = JSONValue.int(root, "pagecount") ?? 1
        return VideoPage(videos: videos, pageCount: max(pageCount, 1))
    }

    // MARK: - 详情

    func detail(for source: SourceBean, videoID: String) async throws -> VodDetail? {
        try validate(source)

        let url = try buildURL(source.api, ["ac": "detail", "ids": videoID])
        let text = try await net.getString(url)

        if source.type == 0 {
            return parseXMLDetail(text, sourceKey: source.key, fallbackID: videoID)
        }

        guard let root = jsonRoot(text),
              let list = root["list"] as? [[String: Any]],
              let first = list.first else {
            return nil
        }

        let video = Video.from(dict: first, sourceKey: source.key)
        let playFrom = JSONValue.string(first, "vod_play_from")
        let playURL = JSONValue.string(first, "vod_play_url")

        return VodDetail.build(video: video, playFrom: playFrom, playURL: playURL)
    }

    // MARK: - 搜索

    func search(in source: SourceBean, keyword: String) async throws -> [Video] {
        try validate(source)

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let url = try buildURL(source.api, ["ac": "videolist", "wd": trimmed, "pg": "1"])
        let text = try await net.getString(url)

        let videos: [Video]
        if source.type == 0 {
            videos = parseXMLVideos(text, sourceKey: source.key)
        } else if let root = jsonRoot(text), let list = root["list"] as? [[String: Any]] {
            videos = list.compactMap { dict -> Video? in
                let video = Video.from(dict: dict, sourceKey: source.key)
                return video.name.isEmpty ? nil : video
            }
        } else {
            videos = []
        }

        return filter(videos, keyword: trimmed)
    }

    /// 多源并发搜索，单个源失败不影响整体。
    func searchAll(sources: [SourceBean], keyword: String) async -> [Video] {
        let usable = sources.filter { $0.isSupported && $0.isHTTP && $0.searchable }
        guard !usable.isEmpty else { return [] }

        return await withTaskGroup(of: [Video].self) { group in
            for source in usable {
                group.addTask {
                    (try? await self.search(in: source, keyword: keyword)) ?? []
                }
            }

            var merged: [Video] = []
            for await result in group {
                merged.append(contentsOf: result)
            }
            return merged
        }
    }

    // MARK: - 校验与工具

    private func validate(_ source: SourceBean) throws {
        guard source.isSupported else { throw VodError.unsupported(source.typeLabel) }
        guard !source.api.isEmpty else { throw VodError.emptyApi }
        guard source.isHTTP else { throw VodError.badURL(source.api) }
    }

    private func buildURL(_ base: String, _ params: [String: String]) throws -> String {
        guard var components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw VodError.badURL(base)
        }

        var items = components.queryItems ?? []
        for (key, value) in params {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items

        guard let url = components.url else { throw VodError.badURL(base) }
        return url.absoluteString
    }

    private func jsonRoot(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    /// 接口有时会返回推荐位等无关内容，这里按关键词做一次本地过滤。
    private func filter(_ videos: [Video], keyword: String) -> [Video] {
        let tokens = keyword
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return videos }

        return videos.filter { video in
            let text = normalize([
                video.name, video.note, video.actor,
                video.director, video.typeName, video.area, video.year
            ].joined(separator: " "))
            guard !text.isEmpty else { return false }
            return tokens.allSatisfy { text.contains($0) }
        }
    }

    private func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        )
        let scalars = folded.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    // MARK: - XML 解析（type = 0）

    private func parseXMLCategories(_ xml: String) -> [VideoCategory] {
        var result: [VideoCategory] = []
        let ns = xml as NSString
        let range = NSRange(location: 0, length: ns.length)

        guard let regex = try? NSRegularExpression(pattern: "<ty\\s+id=\"([^\"]+)\"[^>]*>([^<]*)</ty>") else {
            return []
        }

        for match in regex.matches(in: xml, range: range) where match.numberOfRanges >= 3 {
            let id = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let name = decodeXMLText(ns.substring(with: match.range(at: 2)))
            guard !id.isEmpty, !name.isEmpty else { continue }
            result.append(VideoCategory(id: id, name: name))
        }
        return result
    }

    private func parseXMLVideos(_ xml: String, sourceKey: String) -> [Video] {
        xmlBlocks(xml, tag: "video").compactMap { block in
            let id = xmlTag(block, "id")
            guard !id.isEmpty else { return nil }

            let video = Video(
                id: id,
                name: xmlTag(block, "name"),
                pic: xmlTag(block, "pic"),
                note: xmlTag(block, "note"),
                year: xmlTag(block, "year"),
                area: xmlTag(block, "area"),
                typeName: xmlTag(block, "type"),
                director: xmlTag(block, "director"),
                actor: xmlTag(block, "actor"),
                content: xmlTag(block, "des"),
                sourceKey: sourceKey
            )
            return video.name.isEmpty ? nil : video
        }
    }

    private func parseXMLDetail(_ xml: String, sourceKey: String, fallbackID: String) -> VodDetail? {
        guard let block = xmlBlocks(xml, tag: "video").first else { return nil }

        let id = xmlTag(block, "id")
        let video = Video(
            id: id.isEmpty ? fallbackID : id,
            name: xmlTag(block, "name"),
            pic: xmlTag(block, "pic"),
            note: xmlTag(block, "note"),
            year: xmlTag(block, "year"),
            area: xmlTag(block, "area"),
            typeName: xmlTag(block, "type"),
            director: xmlTag(block, "director"),
            actor: xmlTag(block, "actor"),
            content: xmlTag(block, "des"),
            sourceKey: sourceKey
        )

        let ddNodes = xmlDDNodes(block)
        if ddNodes.isEmpty {
            return VodDetail.build(video: video, playFrom: "默认", playURL: "")
        }

        let flags = ddNodes.map { $0.flag }.joined(separator: "$$$")
        let urls = ddNodes.map { $0.url }.joined(separator: "$$$")
        return VodDetail.build(video: video, playFrom: flags, playURL: urls)
    }

    private func xmlBlocks(_ xml: String, tag: String) -> [String] {
        let ns = xml as NSString
        let range = NSRange(location: 0, length: ns.length)
        let pattern = "<\(tag)(?:\\s[^>]*)?>[\\s\\S]*?</\(tag)>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return regex.matches(in: xml, range: range).map { ns.substring(with: $0.range) }
    }

    private func xmlTag(_ block: String, _ tag: String) -> String {
        let ns = block as NSString
        let range = NSRange(location: 0, length: ns.length)
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let pattern = "<\(escaped)>([\\s\\S]*?)</\(escaped)>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: block, range: range),
              match.numberOfRanges >= 2 else {
            return ""
        }
        return decodeXMLText(ns.substring(with: match.range(at: 1)))
    }

    /// 解析 `<dd flag="线路一">第1集$http://...</dd>` 节点。
    private func xmlDDNodes(_ block: String) -> [(flag: String, url: String)] {
        let ns = block as NSString
        let range = NSRange(location: 0, length: ns.length)

        guard let regex = try? NSRegularExpression(pattern: "<dd([^>]*)>([\\s\\S]*?)</dd>", options: [.caseInsensitive]) else {
            return []
        }

        var result: [(flag: String, url: String)] = []
        for (index, match) in regex.matches(in: block, range: range).enumerated() where match.numberOfRanges >= 3 {
            let attributes = ns.substring(with: match.range(at: 1))
            let content = decodeXMLText(ns.substring(with: match.range(at: 2)))
            guard !content.isEmpty else { continue }

            var flag = "线路\(index + 1)"
            if let flagRegex = try? NSRegularExpression(pattern: "flag\\s*=\\s*[\"']([^\"']+)[\"']"),
               let flagMatch = flagRegex.firstMatch(in: attributes, range: NSRange(location: 0, length: (attributes as NSString).length)),
               flagMatch.numberOfRanges >= 2 {
                flag = decodeXMLText((attributes as NSString).substring(with: flagMatch.range(at: 1)))
            }
            result.append((flag: flag, url: content))
        }
        return result
    }

    private func decodeXMLText(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("<![CDATA["), value.hasSuffix("]]>"), value.count >= 12 {
            value.removeFirst(9)
            value.removeLast(3)
        }

        let replacements: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (from, to) in replacements {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
