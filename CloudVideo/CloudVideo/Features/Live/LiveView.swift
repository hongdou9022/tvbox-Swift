import SwiftUI
import Combine

/// 一个直播频道。
struct LiveChannel: Identifiable, Hashable {
    let name: String
    let urls: [String]
    let group: String

    var id: String { group + "|" + name + "|" + (urls.first ?? "") }
}

/// 直播源解析：兼容 M3U 与「频道名,地址」的 TXT 两种常见格式。
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
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if firstLine.uppercased().hasPrefix("#EXTM3U") {
            return parseM3U(lines: lines, defaultGroup: defaultGroup)
        }
        return parseTXT(lines: lines, defaultGroup: defaultGroup)
    }

    private static func parseM3U(lines: [String], defaultGroup: String) -> [LiveChannel] {
        var result: [LiveChannel] = []
        var pendingName = ""
        var pendingGroup = defaultGroup

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                pendingGroup = defaultGroup
                if let commaIndex = trimmed.range(of: ",", options: .backwards) {
                    pendingName = String(trimmed[commaIndex.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let groupRange = trimmed.range(of: "group-title=\"") {
                    let after = trimmed[groupRange.upperBound...]
                    if let end = after.firstIndex(of: "\"") {
                        let name = String(after[..<end]).trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { pendingGroup = name }
                    }
                }
            } else if !trimmed.hasPrefix("#"), isStreamURL(trimmed) {
                let name = pendingName.isEmpty ? "未命名频道" : pendingName
                result.append(LiveChannel(name: name, urls: [trimmed], group: pendingGroup))
                pendingName = ""
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

            result.append(LiveChannel(name: name, urls: [url], group: currentGroup))
        }

        return result
    }
}

// MARK: - ViewModel

@MainActor
final class LiveViewModel: ObservableObject {
    @Published private(set) var channels: [LiveChannel] = []
    @Published private(set) var groups: [String] = []
    @Published var selectedGroup: String?
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private var loadedKey = ""

    var visibleChannels: [LiveChannel] {
        guard let selectedGroup else { return channels }
        return channels.filter { $0.group == selectedGroup }
    }

    func loadIfNeeded(app: AppState) async {
        let key = app.liveEntries.map { $0.url }.joined(separator: "|")
        guard !key.isEmpty, key != loadedKey else { return }
        loadedKey = key
        await load(app: app)
    }

    func load(app: AppState) async {
        guard !app.liveEntries.isEmpty else {
            channels = []
            groups = []
            return
        }

        isLoading = true
        errorText = nil

        var collected: [LiveChannel] = []

        for entry in app.liveEntries {
            if LiveParser.isStreamURL(entry.url) && !entry.url.lowercased().contains(".m3u") {
                // 配置里直接给出的频道地址
                collected.append(LiveChannel(name: entry.name, urls: [entry.url], group: entry.group))
                continue
            }

            do {
                let content = try await NetworkClient.shared.getString(entry.url)
                collected.append(contentsOf: LiveParser.parse(content, defaultGroup: entry.group))
            } catch {
                // 单个源失败不影响其他源
                continue
            }
        }

        // 同名频道合并线路
        var merged: [String: LiveChannel] = [:]
        for channel in collected {
            let key = channel.group + "|" + channel.name
            if let existing = merged[key] {
                var urls = existing.urls
                for url in channel.urls where !urls.contains(url) {
                    urls.append(url)
                }
                merged[key] = LiveChannel(name: existing.name, urls: urls, group: existing.group)
            } else {
                merged[key] = channel
            }
        }

        channels = merged.values.sorted { $0.name < $1.name }

        var seenGroups: [String] = []
        for channel in channels where !seenGroups.contains(channel.group) {
            seenGroups.append(channel.group)
        }
        groups = seenGroups
        selectedGroup = seenGroups.first

        if channels.isEmpty {
            errorText = "没有解析到可用频道"
        }

        isLoading = false
    }
}

// MARK: - View

struct LiveView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var vm = LiveViewModel()

    @State private var playing: LiveChannel?

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await vm.loadIfNeeded(app: app)
        }
        .fullScreenCover(item: $playing) { channel in
            PlayerView(
                title: channel.name,
                subtitle: channel.group,
                urlString: channel.urls.first ?? "",
                hasNext: channel.urls.count > 1,
                onClose: { playing = nil },
                onNext: {
                    // 多线路时切换到下一条
                    if let current = playing, let first = current.urls.first,
                       let index = current.urls.firstIndex(of: first),
                       index + 1 < current.urls.count {
                        playing = LiveChannel(
                            name: current.name,
                            urls: Array(current.urls.dropFirst(index + 1)) + Array(current.urls.prefix(index + 1)),
                            group: current.group
                        )
                    }
                }
            )
            .id(channel.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("电视直播")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if !vm.channels.isEmpty {
                    Text("\(vm.channels.count) 个频道")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if !vm.groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.groups, id: \.self) { group in
                            Button {
                                vm.selectedGroup = group
                                Haptics.select()
                            } label: {
                                TagChip(text: group, selected: vm.selectedGroup == group)
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if app.liveEntries.isEmpty {
            EmptyStateView(
                icon: "tv.slash",
                title: "配置里没有直播源",
                subtitle: "在配置 JSON 的 lives 字段里加上直播地址即可"
            )
        } else if vm.isLoading && vm.channels.isEmpty {
            VStack {
                Spacer()
                LoadingRow(text: "正在解析直播源")
                Spacer()
            }
        } else if vm.channels.isEmpty {
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "直播源加载失败",
                subtitle: vm.errorText,
                actionTitle: "重试"
            ) {
                Task { await vm.load(app: app) }
            }
        } else {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(vm.visibleChannels) { channel in
                        Button {
                            playing = channel
                        } label: {
                            channelCell(channel)
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.96))
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
        }
    }

    private func channelCell(_ channel: LiveChannel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tv")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)

            Text(channel.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if channel.urls.count > 1 {
                Text("\(channel.urls.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}
