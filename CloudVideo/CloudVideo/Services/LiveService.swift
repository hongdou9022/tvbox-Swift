import Foundation

/// 一个直播频道。
struct LiveChannel: Identifiable, Hashable {
    let name: String
    let group: String
    let url: String
    var logo: String? = nil
    /// 非空时播放器要设置该 UA（接口规范 5.4）。
    var ua: String? = nil

    var id: String { group + "|" + name + "|" + url }
}

/// IPTV 频道解析（规范第 6 章）。
///
/// 首选 `/api/iptv/{id}/channels` 的结构化分组；该接口不可用时
/// 退回解析 `/api/iptv/enabled` 下发的 `content`（内嵌 m3u/txt）或 `url`（订阅地址）。
enum LiveParser {

    static func isStreamURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("rtmp://")
            || lower.hasPrefix("rtsp://")
    }

    static func parse(_ content: String, defaultGroup: String) -> [LiveChannel] {
        let lines = content.components(separatedBy: .newlines)
        let first = lines
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if first.uppercased().hasPrefix("#EXTM3U") {
            return parseM3U(lines: lines, defaultGroup: defaultGroup)
        }
        return parseTXT(lines: lines, defaultGroup: defaultGroup)
    }

    private static func parseM3U(lines: [String], defaultGroup: String) -> [LiveChannel] {
        var result: [LiveChannel] = []
        var pendingName = ""
        var pendingGroup = defaultGroup
        var pendingLogo: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                pendingGroup = defaultGroup
                pendingLogo = nil

                if let comma = trimmed.range(of: ",", options: .backwards) {
                    pendingName = String(trimmed[comma.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let group = attribute("group-title", in: trimmed), !group.isEmpty {
                    pendingGroup = group
                }
                if let logo = attribute("tvg-logo", in: trimmed), !logo.isEmpty {
                    pendingLogo = logo
                }
            } else if !trimmed.hasPrefix("#"), isStreamURL(trimmed) {
                let name = pendingName.isEmpty ? "未命名频道" : pendingName
                result.append(
                    LiveChannel(name: name, group: pendingGroup, url: trimmed, logo: pendingLogo)
                )
                pendingName = ""
                pendingLogo = nil
            }
        }
        return result
    }

    private static func parseTXT(lines: [String], defaultGroup: String) -> [LiveChannel] {
        var result: [LiveChannel] = []
        var currentGroup = defaultGroup

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasSuffix(",#genre#") || trimmed.hasSuffix("，#genre#") {
                let name = trimmed
                    .replacingOccurrences(of: ",#genre#", with: "")
                    .replacingOccurrences(of: "，#genre#", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentGroup = name.isEmpty ? defaultGroup : name
                continue
            }

            let parts = trimmed.components(separatedBy: ",")
            guard parts.count >= 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let url = parts.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, isStreamURL(url) else { continue }

            result.append(LiveChannel(name: name, group: currentGroup, url: url))
        }
        return result
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: "\(key)=\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}

// MARK: - 加载

@MainActor
final class LiveViewModel: ObservableObject {
    @Published private(set) var channels: [LiveChannel] = []
    /// 分组顺序按服务端下发，**不要重排**（接口规范 5.4）。
    @Published private(set) var groups: [String] = []
    @Published var selectedGroup: String?
    @Published private(set) var rooms: [LiveRoom] = []
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let api = APIClient.shared
    private var didLoad = false

    var visibleChannels: [LiveChannel] {
        guard let selectedGroup else { return channels }
        return channels.filter { $0.group == selectedGroup }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await load()
    }

    func load() async {
        isLoading = true
        errorText = nil

        await loadChannels()
        await loadRooms()

        if channels.isEmpty && rooms.isEmpty {
            errorText = "还没有直播源。\n在服务端添加 IPTV 订阅后，频道会出现在这里。"
        }
        isLoading = false
    }

    // MARK: - IPTV 频道

    private func loadChannels() async {
        let sources = (try? await api.iptvSources()) ?? []
        guard !sources.isEmpty else { return }

        var collected: [LiveChannel] = []
        var orderedGroups: [String] = []

        // 第一条即默认源（按 is_default DESC, time DESC 排序）
        for source in sources {
            let payload = try? await api.iptvChannels(sourceId: source.id)

            if let groups = payload?.groups, !groups.isEmpty {
                for group in groups {
                    let groupName = group.name.isEmpty ? source.name : group.name
                    if !orderedGroups.contains(groupName) {
                        orderedGroups.append(groupName)
                    }
                    for channel in group.channels ?? [] {
                        guard let url = channel.firstURL, !url.isEmpty else { continue }
                        collected.append(
                            LiveChannel(
                                name: channel.name,
                                group: groupName,
                                url: url,
                                logo: channel.logo,
                                ua: channel.userAgent
                            )
                        )
                    }
                }
                continue
            }

            // 结构化接口不可用 → 退回内嵌内容 / 订阅地址
            if let inline = source.inlineContent {
                collected.append(contentsOf: LiveParser.parse(inline, defaultGroup: source.name))
                continue
            }
            if let remote = source.remoteURL {
                if let text = await fetchText(remote) {
                    collected.append(contentsOf: LiveParser.parse(text, defaultGroup: source.name))
                }
            }
        }

        // 同名频道合并线路，避免同一个台重复出现
        var merged: [String: LiveChannel] = [:]
        var order: [String] = []
        for channel in collected {
            let key = channel.group + "|" + channel.name
            if merged[key] == nil {
                merged[key] = channel
                order.append(key)
            }
        }
        channels = order.compactMap { merged[$0] }

        var seenGroups = orderedGroups
        for channel in channels where !seenGroups.contains(channel.group) {
            seenGroups.append(channel.group)
        }
        groups = seenGroups
        if selectedGroup == nil || !seenGroups.contains(selectedGroup ?? "") {
            selectedGroup = seenGroups.first
        }
    }

    // MARK: - 直播间

    private func loadRooms() async {
        let page = try? await api.liveRooms(pageSize: 30)
        rooms = (page?.list ?? []).filter { ($0.isActive ?? 1) != 0 }
    }

    /// 取直播间流地址。未开播返回 `nil`，由调用方提示而不是白屏。
    func streamURL(for room: LiveRoom) async -> String? {
        guard let platform = room.platform, let roomId = room.roomId else { return nil }

        let info = try? await api.liveStream(platform: platform, roomId: roomId)
        guard let info, info.isLive else { return nil }
        return info.playURL
    }

    /// 订阅地址是纯文本 m3u/txt，不走 JSON 客户端。
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

        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
