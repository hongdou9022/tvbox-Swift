import Foundation
import Network
import UIKit

/// 局域网内的一台电视。字段对应电视端 `PairingServer` 的 `/v2/info` 响应。
struct CastDevice: Identifiable, Hashable {
    let deviceId: String
    let name: String
    let ip: String
    let port: Int
    let omniHost: String

    var id: String { deviceId }

    /// 规范 5.7-3：`· 已配对` / `· 需在电视上确认`
    func statusText(paired: Bool) -> String {
        paired ? "· 已配对" : "· 需在电视上确认"
    }
}

/// 投屏载荷，与电视端约定一致。
struct CastPayload {
    let sourceType: String
    let libraryId: String
    let videoId: String
    let line: Int
    let episode: Int
    let episodeId: String
    let positionMs: Int64
    let title: String

    var dictionary: [String: Any] {
        [
            "sourceType": sourceType,
            "libraryId": libraryId,
            "videoId": videoId,
            "line": line,
            "episode": episode,
            "episodeId": episodeId,
            "positionMs": positionMs,
            "title": title
        ]
    }
}

enum CastError: LocalizedError {
    case pairFailed(String)
    case lanUnreachable(String)
    case serverFailed(String)

    var errorDescription: String? {
        switch self {
        case .pairFailed(let message): return "配对失败：\(message)"
        case .lanUnreachable(let message): return "电视没有响应（\(message)）"
        case .serverFailed(let message): return "推送失败：\(message)"
        }
    }
}

/// 电视发现与推送。
///
/// 协议来自电视端 `remote/PairingServer`（端口 10081）：
/// - 发现：`GET http://<ip>:10081/v2/info`，返回 `{magic:"OMNIBOX_TV", deviceId, name, port, omniHost}`
/// - 配对：`POST /v2/pair`，body `{deviceId, deviceName}` → `{token}`
/// - 推送：`POST /v2/push`，header `X-Box-Token`，body 为载荷
/// - 局域网失败时回落服务端单槽，电视下次前台收取
@MainActor
final class CastService: ObservableObject {
    static let shared = CastService()

    /// 电视端固定端口
    static let devicePort = 10081
    /// 规范 5.7：扫描窗口 2.6 秒
    static let scanWindow: TimeInterval = 2.6

    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var pairedDeviceIds: Set<String> = []

    private let defaults = UserDefaults.standard

    /// 探测用短超时会话。静态持有，避免在并发任务里捕获 self。
    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 4
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private enum Keys {
        static let tokenPrefix = "cloudvideo.cast.token."
        static let lastDevice = "cloudvideo.cast.lastDevice"
        static let phoneId = "cloudvideo.cast.phoneId"
    }

    private init() {}

    // MARK: - 本机身份

    /// 稳定的手机标识，用于服务端配对记录。
    var phoneId: String {
        if let saved = defaults.string(forKey: Keys.phoneId), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Keys.phoneId)
        return generated
    }

    var phoneName: String {
        UIDevice.current.model
    }

    // MARK: - 配对记录

    func token(for deviceId: String) -> String? {
        let value = defaults.string(forKey: Keys.tokenPrefix + deviceId) ?? ""
        return value.isEmpty ? nil : value
    }

    func isPaired(_ device: CastDevice) -> Bool {
        token(for: device.deviceId) != nil
    }

    private func storeToken(_ token: String, for deviceId: String) {
        defaults.set(token, forKey: Keys.tokenPrefix + deviceId)
        pairedDeviceIds.insert(deviceId)
    }

    /// 上次连过的设备置顶（规范 5.7-5）。
    var lastDevice: CastDevice? {
        guard let data = defaults.data(forKey: Keys.lastDevice),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceId = dict["deviceId"] as? String,
              let ip = dict["ip"] as? String else { return nil }

        return CastDevice(
            deviceId: deviceId,
            name: dict["name"] as? String ?? "电视",
            ip: ip,
            port: dict["port"] as? Int ?? Self.devicePort,
            omniHost: dict["omniHost"] as? String ?? ""
        )
    }

    private func remember(_ device: CastDevice) {
        let dict: [String: Any] = [
            "deviceId": device.deviceId,
            "name": device.name,
            "ip": device.ip,
            "port": device.port,
            "omniHost": device.omniHost
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            defaults.set(data, forKey: Keys.lastDevice)
        }
    }

    // MARK: - 扫描

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        devices = []

        // 规范 5.7-5：上次连过的设备先显示出来
        if let last = lastDevice {
            devices = [last]
        }

        let hosts = Self.candidateAddresses()
        let backendHost = APIClient.shared.baseURL?.host?.lowercased() ?? ""

        var found: [CastDevice] = []
        var seen = Set<String>()

        await withTaskGroup(of: CastDevice?.self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0
            let limit = 24

            // 限制并发，避免 254 个请求同时打出去
            while inFlight < limit, let host = iterator.next() {
                group.addTask { await Self.probe(host: host) }
                inFlight += 1
            }

            for await result in group {
                inFlight -= 1
                if let device = result,
                   !seen.contains(device.deviceId),
                   Self.matchesBackend(device, backendHost: backendHost) {
                    seen.insert(device.deviceId)
                    found.append(device)
                }
                if let host = iterator.next() {
                    group.addTask { await Self.probe(host: host) }
                    inFlight += 1
                }
            }
        }

        // 上次设备置顶，其余按名称排序
        let previous = lastDevice
        found.sort { lhs, rhs in
            if lhs.deviceId == previous?.deviceId { return true }
            if rhs.deviceId == previous?.deviceId { return false }
            return lhs.name < rhs.name
        }

        var merged = found
        if let previous, !merged.contains(where: { $0.deviceId == previous.deviceId }) {
            merged.insert(previous, at: 0)
        }
        devices = merged

        pairedDeviceIds = Set(merged.filter { token(for: $0.deviceId) != nil }.map { $0.deviceId })
        isScanning = false
    }

    /// 只保留同一后端的电视，避免把别人的电视列进来。
    private static func matchesBackend(_ device: CastDevice, backendHost: String) -> Bool {
        guard !device.omniHost.isEmpty, !backendHost.isEmpty else { return true }
        return device.omniHost.lowercased() == backendHost
    }

    private static func probe(host: String) async -> CastDevice? {
        guard let url = URL(string: "http://\(host):\(Self.devicePort)/v2/info") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 1.5

        guard let (data, response) = try? await probeSession.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard object["magic"] as? String == "OMNIBOX_TV",
              let deviceId = object["deviceId"] as? String,
              !deviceId.isEmpty else {
            return nil
        }

        let port = (object["port"] as? Int) ?? Self.devicePort
        return CastDevice(
            deviceId: deviceId,
            name: object["name"] as? String ?? "电视",
            ip: host,
            port: port > 0 ? port : Self.devicePort,
            omniHost: object["omniHost"] as? String ?? ""
        )
    }

    /// 本机所有 IPv4 网段的 /24 全量地址 + 回环。
    private static func candidateAddresses() -> [String] {
        var result: [String] = ["127.0.0.1"]
        var seen = Set(result)

        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return result }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, !isLoopback,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if let dot = ip.lastIndex(of: ".") {
                        let prefix = String(ip[..<dot])
                        for index in 1...254 {
                            let candidate = "\(prefix).\(index)"
                            if seen.insert(candidate).inserted {
                                result.append(candidate)
                            }
                        }
                    }
                }
            }
            pointer = current.pointee.ifa_next
        }

        return result
    }

    // MARK: - 推送

    /// 规范 5.7：已配对直接推；未配对先配对（电视上确认）再推。
    func push(_ payload: CastPayload, to device: CastDevice) async throws -> String {
        // 注意不要用 token 命名局部变量，会遮蔽下面的 token(for:) 方法
        let pairToken: String
        if let existing = token(for: device.deviceId) {
            pairToken = existing
        } else {
            pairToken = try await pair(device)
        }

        do {
            try await sendPush(payload, to: device, token: pairToken)
            remember(device)
            return "已推送到电视"
        } catch {
            // 局域网不可达 → 回落服务端单槽
            try await pushViaServer(payload, to: device, token: pairToken)
            remember(device)
            return "已发送到服务器，电视下次前台时收取"
        }
    }

    private func pair(_ device: CastDevice) async throws -> String {
        let body: [String: Any] = [
            "deviceId": phoneId,
            "deviceName": phoneName
        ]
        let response = try await post(
            to: device,
            path: "/v2/pair",
            body: body,
            token: nil,
            timeout: 20
        )
        guard let newToken = response["token"] as? String, !newToken.isEmpty else {
            throw CastError.pairFailed("电视没有返回配对令牌")
        }
        storeToken(newToken, for: device.deviceId)
        return newToken
    }

    private func sendPush(_ payload: CastPayload, to device: CastDevice, token: String) async throws {
        _ = try await post(
            to: device,
            path: "/v2/push",
            body: payload.dictionary,
            token: token,
            timeout: 4
        )
    }

    private func pushViaServer(_ payload: CastPayload, to device: CastDevice, token: String) async throws {
        do {
            try await APIClient.shared.pairDevice(
                deviceId: device.deviceId,
                pairToken: token,
                phoneId: phoneId,
                phoneName: phoneName
            )
        } catch {
            // 配对记录已存在时会报错，忽略即可
        }
        try await APIClient.shared.pushToDevice(
            deviceId: device.deviceId,
            pairToken: token,
            phoneId: phoneId,
            payload: payload.dictionary
        )
    }

    private func post(
        to device: CastDevice,
        path: String,
        body: [String: Any],
        token: String?,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        guard let url = URL(string: "http://\(device.ip):\(device.port)\(path)") else {
            throw CastError.lanUnreachable("地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Box-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CastError.lanUnreachable(error.localizedDescription)
        }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CastError.lanUnreachable(object["message"] as? String ?? "HTTP \(http.statusCode)")
        }
        return object
    }

    // MARK: - 遥控（接口规范 4.14.6，电视端 /v2/state 与 /v2/command）

    /// 电视播放状态。`position/duration` 单位是**毫秒**。
    struct RemoteState {
        let hasPlayer: Bool
        let playing: Bool
        let position: Int
        let duration: Int
        let title: String
        /// 从 0 开始；无播放器时为 -1
        let index: Int
        let count: Int
        let foreground: Bool

        var progressRatio: Double {
            guard duration > 0 else { return 0 }
            return min(max(Double(position) / Double(duration), 0), 1)
        }

        var statusText: String {
            if !hasPlayer { return "电视没有在播放" }
            if !foreground { return "电视当前不在前台" }
            return playing ? "正在播放" : "已暂停"
        }
    }

    /// 遥控指令（接口规范 4.14.6 的指令表）。
    enum RemoteCommand {
        case up, down, left, right
        case ok
        case back
        case play, pause, toggle
        case next, prev
        case forward, backward
        case seek

        var name: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .ok: return "ok"
            case .back: return "back"
            case .play: return "play"
            case .pause: return "pause"
            case .toggle: return "toggle"
            case .next: return "next"
            case .prev: return "prev"
            case .forward: return "forward"
            case .backward: return "backward"
            case .seek: return "seek"
            }
        }
    }

    /// 读取电视播放状态。
    func fetchState(for device: CastDevice) async throws -> RemoteState {
        let pairToken = try await ensurePaired(device)
        guard let url = URL(string: "http://\(device.ip):\(device.port)/v2/state") else {
            throw CastError.lanUnreachable("地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(pairToken, forHTTPHeaderField: "X-Box-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CastError.lanUnreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CastError.lanUnreachable("电视没有响应")
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        return RemoteState(
            hasPlayer: object["hasPlayer"] as? Bool ?? false,
            playing: object["playing"] as? Bool ?? false,
            position: object["position"] as? Int ?? 0,
            duration: object["duration"] as? Int ?? 0,
            title: object["title"] as? String ?? "",
            index: object["index"] as? Int ?? -1,
            count: object["count"] as? Int ?? 0,
            foreground: object["foreground"] as? Bool ?? false
        )
    }

    /// 发一条遥控指令。失败时返回服务端文案，由界面原样展示。
    func sendCommand(
        _ command: RemoteCommand,
        value: Int? = nil,
        to device: CastDevice
    ) async -> String? {
        do {
            let pairToken = try await ensurePaired(device)

            var body: [String: Any] = ["cmd": command.name]
            if let value {
                body["value"] = value
            }

            let response = try await post(
                to: device,
                path: "/v2/command",
                body: body,
                token: pairToken,
                timeout: 5
            )

            if response["ok"] as? Bool == false {
                return response["message"] as? String ?? "电视没有响应"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 让电视直接搜索某个关键词（遥控页的「在电视上搜索」）。
    func searchOnTV(_ keyword: String, device: CastDevice) async -> String? {
        do {
            let pairToken = try await ensurePaired(device)
            let response = try await post(
                to: device,
                path: "/v2/command",
                body: ["cmd": "search", "keyword": keyword],
                token: pairToken,
                timeout: 5
            )
            if response["ok"] as? Bool == false {
                return response["message"] as? String ?? "电视没有响应"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 已配对直接返回本地 token，未配对先走 `/v2/pair`（电视上会弹确认）。
    func ensurePaired(_ device: CastDevice) async throws -> String {
        if let existing = token(for: device.deviceId) {
            return existing
        }
        return try await pair(device)
    }

    // MARK: - 配对管理（接口规范 4.14.7）

    func pairs(for deviceId: String) async throws -> [DevicePair] {
        let payload = try await APIClient.shared.devicePairs(deviceId: deviceId)
        return payload.pairs ?? []
    }

    func updateNote(deviceId: String, phoneId: String, note: String) async throws {
        try await APIClient.shared.updatePairNote(deviceId: deviceId, phoneId: phoneId, note: note)
    }

    /// 删除配对：服务端对不存在的记录也回成功，按「已删除」处理即可。
    func removePair(deviceId: String, phoneId: String) async throws {
        try await APIClient.shared.deletePair(deviceId: deviceId, phoneId: phoneId)
        if phoneId == self.phoneId {
            defaults.removeObject(forKey: Keys.tokenPrefix + deviceId)
            pairedDeviceIds.remove(deviceId)
        }
    }
}
