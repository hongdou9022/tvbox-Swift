import Foundation

/// 解析后的配置内容。
struct ParsedConfig {
    var sources: [SourceBean]
    var liveEntries: [LiveEntry]
    var wallpaper: String
    /// 如果这个地址其实是一个"多仓库入口"，这里会带上可选的子地址。
    var repositoryURLs: [String]

    var hasContent: Bool {
        !sources.isEmpty || !liveEntries.isEmpty || !repositoryURLs.isEmpty
    }
}

/// TVBox 配置 JSON 解析器。
///
/// 之所以用 `JSONSerialization` 而不是 `Codable`，是因为配置文件里的字段类型很不统一：
/// `searchable` 可能是 `1` / `"1"` / `true`，`ext` 可能是字符串也可能是对象。
/// 手写取值容错成本更低，也更容易定位问题。
enum ConfigParser {

    static func parse(_ text: String) -> ParsedConfig? {
        let cleaned = stripComments(text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let root = object as? [String: Any] else { return nil }

        var sources: [SourceBean] = []

        if let sites = root["sites"] as? [[String: Any]] {
            for (index, site) in sites.enumerated() {
                let api = JSONValue.string(site, "api")
                guard !api.isEmpty else { continue }

                var key = JSONValue.string(site, "key")
                if key.isEmpty { key = "site_\(index)" }

                let name = JSONValue.string(site, "name")
                let type = JSONValue.int(site, "type") ?? 1
                let searchable = flag(site["searchable"], defaultValue: 1) == 1
                let filterable = flag(site["filterable"], defaultValue: 1) == 1
                let ext = JSONValue.string(site, "ext")

                sources.append(
                    SourceBean(
                        key: key,
                        name: name.isEmpty ? "未命名源" : name,
                        api: api,
                        type: type,
                        searchable: searchable,
                        filterable: filterable,
                        ext: ext.isEmpty ? nil : ext
                    )
                )
            }
        }

        var liveEntries: [LiveEntry] = []
        if let lives = root["lives"] as? [[String: Any]] {
            for (index, live) in lives.enumerated() {
                let name = JSONValue.string(live, "name")
                let group = JSONValue.string(live, "group")
                let url = JSONValue.string(live, "url")

                if !url.isEmpty {
                    liveEntries.append(
                        LiveEntry(
                            name: name.isEmpty ? "直播源\(index + 1)" : name,
                            url: url,
                            group: group.isEmpty ? "默认" : group
                        )
                    )
                }

                // 内嵌频道（channels 数组）
                if let channels = live["channels"] as? [[String: Any]] {
                    for channel in channels {
                        let channelName = JSONValue.string(channel, "name")
                        let channelGroup = JSONValue.string(channel, "group")
                        let urls = channel["urls"] as? [String] ?? []
                        for (urlIndex, channelURL) in urls.enumerated() {
                            guard !channelURL.isEmpty else { continue }
                            liveEntries.append(
                                LiveEntry(
                                    name: channelName.isEmpty ? "频道\(urlIndex + 1)" : channelName,
                                    url: channelURL,
                                    group: channelGroup.isEmpty ? (group.isEmpty ? "默认" : group) : channelGroup
                                )
                            )
                        }
                    }
                }
            }
        }

        var repositoryURLs: [String] = []
        if let urls = root["urls"] as? [[String: Any]] {
            for item in urls {
                let url = JSONValue.string(item, "url")
                if !url.isEmpty { repositoryURLs.append(url) }
            }
        } else if let plain = root["urls"] as? [String] {
            repositoryURLs = plain.filter { !$0.isEmpty }
        }

        let wallpaper = JSONValue.string(root, "wallpaper")

        return ParsedConfig(
            sources: sources,
            liveEntries: liveEntries,
            wallpaper: wallpaper,
            repositoryURLs: repositoryURLs
        )
    }

    // MARK: - 容错取值

    /// `searchable` 这类字段可能是数字、字符串或布尔。
    private static func flag(_ raw: Any?, defaultValue: Int) -> Int {
        guard let raw, !(raw is NSNull) else { return defaultValue }
        if let number = raw as? NSNumber { return number.intValue }
        if let text = raw as? String { return Int(text) ?? defaultValue }
        return defaultValue
    }

    // MARK: - JSON 预处理

    /// TVBox 配置普遍带 `//` 注释，标准 JSON 解析器会直接失败。
    /// 这里做一次扫描，跳过字符串内部的 `//`，同时清理注释留下的多余逗号。
    static func stripComments(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)

        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            if escaped {
                output.append(char)
                escaped = false
                index = text.index(after: index)
                continue
            }

            if char == "\\" && inString {
                output.append(char)
                escaped = true
                index = text.index(after: index)
                continue
            }

            if char == "\"" {
                inString.toggle()
                output.append(char)
                index = text.index(after: index)
                continue
            }

            if !inString && char == "/" {
                let next = text.index(after: index)

                if next < text.endIndex && text[next] == "/" {
                    var cursor = next
                    while cursor < text.endIndex && text[cursor] != "\n" {
                        cursor = text.index(after: cursor)
                    }
                    index = cursor
                    continue
                }

                if next < text.endIndex && text[next] == "*" {
                    var cursor = text.index(after: next)
                    while cursor < text.endIndex {
                        let after = text.index(after: cursor)
                        if text[cursor] == "*", after < text.endIndex, text[after] == "/" {
                            cursor = text.index(after: after)
                            break
                        }
                        cursor = text.index(after: cursor)
                    }
                    index = cursor
                    continue
                }
            }

            output.append(char)
            index = text.index(after: index)
        }

        // 去掉 `,]` / `,}` 这类因删除注释产生的尾逗号
        return output.replacingOccurrences(
            of: ",\\s*([\\]\\}])",
            with: "$1",
            options: .regularExpression
        )
    }

    /// 修正常见的配置地址写法问题：
    /// - `https:/xxx` 单斜杠
    /// - `github.com/.../blob/...` → `raw.githubusercontent.com/...`
    static func normalize(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return url }

        url = url.replacingOccurrences(of: #"^https:/(?!/)"#, with: "https://", options: .regularExpression)
        url = url.replacingOccurrences(of: #"^http:/(?!/)"#, with: "http://", options: .regularExpression)

        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return url
        }

        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 5, parts[2] == "blob" else { return url }

        let owner = String(parts[0])
        let repo = String(parts[1])
        let branch = String(parts[3])
        let filePath = parts.dropFirst(4).joined(separator: "/")

        var result = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(filePath)"
        if let query = components.percentEncodedQuery, !query.isEmpty {
            result += "?\(query)"
        }
        return result
    }
}
