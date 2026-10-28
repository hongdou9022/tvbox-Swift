import Foundation

/// 弹幕解析与拉取。
///
/// 后端 `POST /api/app/v1/danmaku` 只按 `fileName` 返回**弹幕文件列表**
/// （`[{name, url}]`），真正的弹幕内容要客户端自己下载再解析。
/// `fileName` 的拼法与电视端一致：`片名 年份 集名`，空项跳过。
@MainActor
final class DanmakuService {
    static let shared = DanmakuService()

    private var cache: [String: [DanmakuComment]] = [:]

    private init() {}

    func load(title: String, year: String, episode: String) async -> [DanmakuComment] {
        let fileName = buildFileName(title: title, year: year, episode: episode)
        guard !fileName.isEmpty else { return [] }

        if let cached = cache[fileName] {
            return cached
        }

        guard let files = try? await APIClient.shared.danmakuFiles(fileName: fileName),
              let target = files.first(where: { !$0.url.isEmpty }) else {
            cache[fileName] = []
            return []
        }

        guard let content = await fetchText(target.url) else {
            return []
        }

        let comments = parse(content)
        cache[fileName] = comments
        return comments
    }

    private func buildFileName(title: String, year: String, episode: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "" }

        var parts = [trimmedTitle]
        let trimmedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedYear.isEmpty { parts.append(trimmedYear) }

        let trimmedEpisode = episode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEpisode.isEmpty { parts.append(trimmedEpisode) }

        return parts.joined(separator: " ")
    }

    private func fetchText(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }

        // 弹幕文件常见 GBK 编码
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gbk = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let text = String(data: data, encoding: String.Encoding(rawValue: gbk)) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 解析

    /// 兼容三种常见格式：B 站 XML、JSON 数组、纯文本行。
    func parse(_ content: String) -> [DanmakuComment] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("<d p=") {
            return parseXML(trimmed)
        }
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            if let json = parseJSON(trimmed), !json.isEmpty {
                return json
            }
        }
        return parsePlain(trimmed)
    }

    /// `<d p="12.34,1,25,16777215,1690000000,0,abc,123">弹幕文本</d>`
    private func parseXML(_ content: String) -> [DanmakuComment] {
        let pattern = "<d\\s+p=\"([^\"]*)\"[^>]*>([^<]*)</d>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = content as NSString
        let range = NSRange(location: 0, length: ns.length)

        var result: [DanmakuComment] = []
        for match in regex.matches(in: content, range: range) where match.numberOfRanges >= 3 {
            let attribute = ns.substring(with: match.range(at: 1))
            let text = decodeEntities(ns.substring(with: match.range(at: 2)))
            guard !text.isEmpty else { continue }

            let fields = attribute.components(separatedBy: ",")
            guard let time = Double(fields.first ?? "") else { continue }

            let mode = fields.count > 1 ? (Int(fields[1]) ?? 1) : 1
            let color = fields.count > 3 ? UInt32(fields[3]) ?? 0xFFFFFF : 0xFFFFFF

            result.append(
                DanmakuComment(
                    id: "\(result.count)-\(time)",
                    time: time,
                    text: text,
                    color: color,
                    mode: mode
                )
            )
        }
        return result.sorted { $0.time < $1.time }
    }

    private func parseJSON(_ content: String) -> [DanmakuComment]? {
        guard let data = content.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var result: [DanmakuComment] = []
        for (index, item) in array.enumerated() {
            // 有的源用 {p: "time,mode,...", m: "文本"}，有的直接给 time/text
            if let p = item["p"] as? String, let m = item["m"] as? String {
                let fields = p.components(separatedBy: ",")
                guard let time = Double(fields.first ?? ""), !m.isEmpty else { continue }
                let mode = fields.count > 1 ? (Int(fields[1]) ?? 1) : 1
                let color = fields.count > 3 ? UInt32(fields[3]) ?? 0xFFFFFF : 0xFFFFFF
                result.append(
                    DanmakuComment(id: "j\(index)", time: time, text: m, color: color, mode: mode)
                )
                continue
            }

            let time = (item["time"] as? Double)
                ?? (item["time"] as? NSNumber)?.doubleValue
                ?? Double(item["time"] as? String ?? "")
            let text = (item["text"] as? String) ?? (item["content"] as? String) ?? ""
            guard let time, !text.isEmpty else { continue }

            let color = UInt32((item["color"] as? NSNumber)?.intValue ?? 0xFFFFFF)
            let mode = (item["mode"] as? NSNumber)?.intValue ?? 1
            result.append(
                DanmakuComment(id: "j\(index)", time: time, text: text, color: color, mode: mode)
            )
        }

        return result.sorted { $0.time < $1.time }
    }

    /// `12.34,弹幕文本` 或 `[12.34]弹幕文本`
    private func parsePlain(_ content: String) -> [DanmakuComment] {
        var result: [DanmakuComment] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var timeText: String?
            var body: String?

            if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
                timeText = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                body = String(trimmed[trimmed.index(after: end)...])
            } else if let comma = trimmed.firstIndex(of: ",") {
                timeText = String(trimmed[..<comma])
                body = String(trimmed[trimmed.index(after: comma)...])
            }

            guard let timeText, let time = Double(timeText.trimmingCharacters(in: .whitespaces)),
                  let body else { continue }

            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            result.append(
                DanmakuComment(
                    id: "p\(result.count)",
                    time: time,
                    text: text,
                    color: 0xFFFFFF,
                    mode: 1
                )
            )
        }

        return result.sorted { $0.time < $1.time }
    }

    private func decodeEntities(_ raw: String) -> String {
        var value = raw
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
