import Foundation

enum APIError: LocalizedError {
    case badAddress
    case unauthorized(String)
    case server(String)
    case decoding
    case transport(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .badAddress:
            return "服务器地址格式不正确"
        case .unauthorized(let message):
            return message.isEmpty ? "登录已失效，请重新登录" : message
        case .server(let message):
            return message
        case .decoding:
            return "服务器返回了无法解析的数据"
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .notFound(let message):
            return message.isEmpty ? "接口不存在（服务端版本过旧？）" : message
        }
    }
}

/// 本地源配置的拉取结果：304 时沿用本地缓存。
enum LocalSourcesResult {
    case notModified
    case fresh(LocalSources, String?)
}

/// 对接后端第一方客户端接口（`internal/routes/app.go`）与管理端复用接口。
///
/// 统一约定：
/// - 除 `health` 与登录外全部需要 `Authorization: Bearer <token>`
/// - 响应体统一为 `{code, message, data, success}`
/// - 写操作只校验 `success`，不要求 `data` 存在（收藏成功返回 `data:null`）
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// 搜索用短超时会话：单源预算 3.5s（SEARCH_OPTIMIZATION 2.4）。
    private let searchSession: URLSession
    private let decoder = JSONDecoder()

    private(set) var baseURL: URL?
    private(set) var token: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 8
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        let searchConfig = URLSessionConfiguration.ephemeral
        searchConfig.timeoutIntervalForRequest = 3.5
        searchConfig.timeoutIntervalForResource = 6
        searchConfig.httpMaximumConnectionsPerHost = 8
        searchConfig.waitsForConnectivity = false
        searchSession = URLSession(configuration: searchConfig)
    }

    // MARK: - 会话

    /// 规范 1.1：地址允许不带协议，自动补 `http://`，末尾 `/` 自动去掉。
    static func normalizeServer(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return URL(string: text)
    }

    func configure(server: URL, token: String?) {
        baseURL = server
        self.token = token
    }

    func updateToken(_ token: String?) {
        self.token = token
    }

    /// 当前服务器 host（不含端口），投屏发现时用来过滤别人的电视。
    var baseHost: String? {
        baseURL?.host
    }

    // MARK: - 探活（接口规范 4.0）

    /// 登录前先探活，用来区分「地址填错」和「账号密码错」。
    /// 探活失败不要把用户留在「密码错误」的提示里。
    func health(server: String) async -> Bool {
        guard let url = Self.normalizeServer(server) else { return false }

        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            // `{ "status": "ok", ... }`
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return (object["status"] as? String) == "ok"
        } catch {
            return false
        }
    }

    // MARK: - 登录

    func login(server: String, username: String, password: String) async throws -> LoginResponse {
        guard let url = Self.normalizeServer(server) else { throw APIError.badAddress }

        let body = try JSONEncoder().encode(["username": username, "password": password])
        let response: LoginResponse = try await send(
            url: url.appendingPathComponent("api/app/v1/auth/login"),
            method: "POST",
            body: body,
            authorized: false
        )
        guard !response.token.isEmpty else {
            throw APIError.server("服务端未返回有效令牌")
        }
        baseURL = url
        token = response.token
        return response
    }

    // MARK: - 首页

    func home() async throws -> HomePayload {
        try await get("api/app/v1/home")
    }

    func recommend() async throws -> RecommendHome {
        try await get("api/app/v1/recommend")
    }

    func category(libraryId: String, categoryId: String, page: Int) async throws -> CategoryPage {
        try await get("api/app/v1/category", query: [
            URLQueryItem(name: "libraryId", value: libraryId),
            URLQueryItem(name: "categoryId", value: categoryId),
            URLQueryItem(name: "page", value: "\(page)")
        ])
    }

    /// 豆瓣分类分页（接口规范 5.6）：`start` 是偏移量，不是页码，服务端固定 limit=18。
    func doubanRecommendation(
        primary: String,
        secondary: String,
        tertiary: String,
        start: Int
    ) async throws -> DoubanPage {
        try await get("api/douban-recommendation", query: [
            URLQueryItem(name: "primaryCategory", value: primary),
            URLQueryItem(name: "secondaryCategory", value: secondary),
            URLQueryItem(name: "tertiaryType", value: tertiary),
            URLQueryItem(name: "start", value: "\(start)")
        ])
    }

    /// 首页横幅（接口规范 5.7）。
    func tencentBanner() async throws -> BannerPayload {
        try await get("api/proxy/tencent-banner-data")
    }

    // MARK: - 详情与播放

    func media(
        libraryId: String,
        videoId: String,
        sourceType: String,
        sourceExtra: String? = nil
    ) async throws -> MediaDetail {
        var items = [
            URLQueryItem(name: "libraryId", value: libraryId),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "sourceType", value: sourceType)
        ]
        if let sourceExtra, !sourceExtra.isEmpty {
            items.append(URLQueryItem(name: "source", value: sourceExtra))
        }
        return try await get("api/app/v1/media", query: items)
    }

    func play(
        libraryId: String,
        videoId: String,
        line: Int,
        episode: Int,
        sourceType: String,
        sourceExtra: String? = nil
    ) async throws -> PlayInfo {
        var items = [
            URLQueryItem(name: "libraryId", value: libraryId),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "line", value: "\(line)"),
            URLQueryItem(name: "episode", value: "\(episode)"),
            URLQueryItem(name: "sourceType", value: sourceType)
        ]
        if let sourceExtra, !sourceExtra.isEmpty {
            items.append(URLQueryItem(name: "source", value: sourceExtra))
        }
        return try await get("api/app/v1/play", query: items)
    }

    // MARK: - 续播与进度

    func resume(limit: Int = 12) async throws -> [ResumeItem] {
        try await get("api/app/v1/resume", query: [
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
    }

    /// 进度上报是**唯一**写入入口（接口规范 6.2）。
    /// `libraryId` / `videoId` / `playId` 任一为空时客户端直接不发。
    func saveProgress(
        libraryId: String,
        videoId: String,
        title: String,
        poster: String,
        playId: String,
        episodeName: String,
        positionMs: Int64,
        durationMs: Int64
    ) async throws {
        guard !libraryId.isEmpty, !videoId.isEmpty, !playId.isEmpty else { return }

        let payload: [String: Any] = [
            "libraryId": libraryId,
            "videoId": videoId,
            "title": title,
            "poster": poster,
            "playId": playId,
            "episodeName": episodeName,
            "positionMs": positionMs,
            "durationMs": durationMs
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await sendIgnoringPayload(url: try endpoint("api/app/v1/progress"), method: "POST", body: body)
    }

    /// 观看历史（接口规范 5.2）：返回全部历史，时长单位是**秒**。
    func playHistory(page: Int = 1, pageSize: Int = 20) async throws -> PlayHistoryPage {
        try await get("api/play-history", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ])
    }

    func deletePlayHistory(id: String) async throws {
        try await sendIgnoringPayload(url: try endpoint("api/play-history/\(id)"), method: "DELETE", body: nil)
    }

    func clearPlayHistory() async throws {
        try await sendIgnoringPayload(url: try endpoint("api/play-history"), method: "DELETE", body: nil)
    }

    /// 追剧列表（接口规范 5.3）。
    func watchFollow(page: Int = 1, size: Int = 20) async throws -> WatchFollowPage {
        try await get("api/watch-follow", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)")
        ])
    }

    func deleteWatchFollow(tmdbId: Int, mediaType: String, seasonNumber: Int) async throws {
        try await sendIgnoringPayload(
            url: try endpoint("api/watch-follow", query: [
                URLQueryItem(name: "tmdbId", value: "\(tmdbId)"),
                URLQueryItem(name: "mediaType", value: mediaType),
                URLQueryItem(name: "seasonNumber", value: "\(seasonNumber)")
            ]),
            method: "DELETE",
            body: nil
        )
    }

    // MARK: - 搜索

    /// 服务端聚合搜索（接口规范 4.7）。
    func search(
        keyword: String,
        page: Int,
        sourceId: String? = nil,
        siteId: String? = nil,
        includeSites: Bool = false
    ) async throws -> SearchPage {
        var items = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if let sourceId, !sourceId.isEmpty {
            items.append(URLQueryItem(name: "sourceId", value: sourceId))
        }
        if let siteId, !siteId.isEmpty {
            items.append(URLQueryItem(name: "siteId", value: siteId))
        }
        if includeSites {
            items.append(URLQueryItem(name: "includeSites", value: "1"))
        }
        return try await get("api/app/v1/search", query: items)
    }

    /// 单个影视站的搜索（`/api/site-media/{id}/search`），用短超时会话。
    /// 这是客户端逐源并发的通道，配合滑动窗口调度使用。
    func siteSearch(siteId: String, keyword: String, page: Int) async throws -> SiteSearchPage {
        try await getWith(
            session: searchSession,
            path: "api/site-media/\(siteId)/search",
            query: [
                URLQueryItem(name: "wd", value: keyword),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
    }

    func searchSources() async throws -> [SearchSource] {
        try await get("api/app/v1/search-sources")
    }

    /// 本地源配置（接口规范 4.9）：带 ETag 条件请求，未变返回 304。
    func localSources(etag: String?) async throws -> LocalSourcesResult {
        var request = URLRequest(url: try endpoint("api/app/v1/local-sources"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("服务器没有返回有效响应")
        }
        if http.statusCode == 304 {
            return .notModified
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized("登录已失效，请重新登录")
        }
        guard let envelope = try? decoder.decode(APIEnvelope<LocalSources>.self, from: data),
              envelope.success, let payload = envelope.data else {
            throw APIError.decoding
        }
        let newEtag = http.value(forHTTPHeaderField: "ETag")
        return .fresh(payload, newEtag)
    }

    // MARK: - 收藏（按 影片ID + 来源ID 唯一）

    func favoriteStatus(vodId: String, sourceId: String) async throws -> FavoriteStatus {
        try await get("api/favorite/check", query: [
            URLQueryItem(name: "vodId", value: vodId),
            URLQueryItem(name: "sourceId", value: sourceId)
        ])
    }

    @discardableResult
    func addFavorite(
        title: String,
        vodId: String,
        sourceId: String,
        coverImage: String,
        remark: String,
        rating: Double
    ) async throws -> FavoriteStatus {
        let payload: [String: Any] = [
            "title": title,
            "vodId": vodId,
            "sourceId": sourceId,
            "coverImage": coverImage,
            "remark": remark,
            "rating": rating,
            // 接口规范 5.1：多端按端名传，便于统计来源
            "extraInfo": "ios"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await sendIgnoringPayload(url: try endpoint("api/favorite"), method: "POST", body: body)
        return FavoriteStatus(isFavorited: true, favorite: nil)
    }

    func removeFavorite(id: String) async throws {
        try await sendIgnoringPayload(url: try endpoint("api/favorite/\(id)"), method: "DELETE", body: nil)
    }

    func favorites(page: Int = 1, pageSize: Int = 30) async throws -> FavoriteListPage {
        try await get("api/favorite", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ])
    }

    // MARK: - 设备（推送到电视的服务端兜底通道）

    func registerDevice(deviceId: String, name: String, type: String = "phone", platform: String = "ios") async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "deviceId": deviceId,
            "name": name,
            "type": type,
            "platform": platform
        ])
        try await sendIgnoringPayload(
            url: try endpoint("api/app/v1/devices/register"),
            method: "POST",
            body: body
        )
    }

    func pairDevice(
        deviceId: String,
        pairToken: String,
        phoneId: String,
        phoneName: String,
        note: String = ""
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "pairToken": pairToken,
            "phoneId": phoneId,
            "phoneName": phoneName,
            "note": note
        ])
        try await sendIgnoringPayload(
            url: try endpoint("api/app/v1/devices/\(deviceId)/pair"),
            method: "POST",
            body: body
        )
    }

    func pushToDevice(deviceId: String, pairToken: String, phoneId: String, payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "pairToken": pairToken,
            "phoneId": phoneId,
            "payload": payload
        ])
        try await sendIgnoringPayload(
            url: try endpoint("api/app/v1/devices/\(deviceId)/push"),
            method: "POST",
            body: body
        )
    }

    /// 配对列表（接口规范 4.14.7）。
    func devicePairs(deviceId: String) async throws -> DevicePairList {
        try await get("api/app/v1/devices/\(deviceId)/pairs")
    }

    func updatePairNote(deviceId: String, phoneId: String, note: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["note": note])
        try await sendIgnoringPayload(
            url: try endpoint("api/app/v1/devices/\(deviceId)/pairs/\(phoneId)"),
            method: "PUT",
            body: body
        )
    }

    func deletePair(deviceId: String, phoneId: String) async throws {
        try await sendIgnoringPayload(
            url: try endpoint("api/app/v1/devices/\(deviceId)/pairs/\(phoneId)"),
            method: "DELETE",
            body: nil
        )
    }

    // MARK: - 直播

    func iptvSources() async throws -> [IPTVSource] {
        try await get("api/iptv/enabled")
    }

    /// 频道列表（接口规范 5.4）：`groups` 有序，客户端按序展示不要重排。
    func iptvChannels(sourceId: String) async throws -> IPTVChannelPayload {
        try await get("api/iptv/\(sourceId)/channels")
    }

    /// 直播间列表（接口规范 5.5）。
    func liveRooms(page: Int = 1, pageSize: Int = 30, search: String? = nil) async throws -> LiveRoomPage {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let search, !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        return try await get("api/live-room", query: items)
    }

    /// 直播流（接口规范 5.5）：`status=0` 表示未开播。
    func liveStream(platform: String, roomId: String) async throws -> LiveStreamInfo {
        try await get("api/live/stream/\(platform)/\(roomId)")
    }

    // MARK: - 弹幕

    func danmakuFiles(fileName: String) async throws -> [DanmakuFile] {
        let body = try JSONSerialization.data(withJSONObject: ["fileName": fileName])
        let data = try await perform(
            url: try endpoint("api/app/v1/danmaku"),
            method: "POST",
            body: body,
            authorized: true
        )
        guard let envelope = try? decoder.decode(APIEnvelope<[DanmakuFile]>.self, from: data) else {
            throw APIError.decoding
        }
        guard envelope.success, envelope.code == 200 else {
            throw APIError.server(envelope.message ?? "获取弹幕失败")
        }
        // url 为空的条目客户端直接丢弃
        return (envelope.data ?? []).filter { !$0.url.isEmpty }
    }

    // MARK: - 内部

    private struct EmptyPayload: Decodable {}

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let baseURL else { throw APIError.badAddress }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.badAddress }

        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.badAddress }
        return url
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await getWith(session: session, path: path, query: query)
    }

    private func getWith<T: Decodable>(
        session target: URLSession,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var request = URLRequest(url: try endpoint(path, query: query))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await target.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("服务器没有返回有效响应")
        }
        try Self.checkStatus(http.statusCode, data: data, decoder: decoder)

        guard let envelope = try? decoder.decode(APIEnvelope<T>.self, from: data) else {
            throw APIError.decoding
        }
        guard envelope.success, envelope.code == 200 else {
            throw APIError.server(envelope.message ?? "请求失败（\(envelope.code)）")
        }
        guard let payload = envelope.data else {
            throw APIError.decoding
        }
        return payload
    }

    private func send<T: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        authorized: Bool = true
    ) async throws -> T {
        let data = try await perform(url: url, method: method, body: body, authorized: authorized)

        guard let envelope = try? decoder.decode(APIEnvelope<T>.self, from: data) else {
            throw APIError.decoding
        }
        guard envelope.success, envelope.code == 200 else {
            throw APIError.server(envelope.message ?? "请求失败（\(envelope.code)）")
        }
        guard let payload = envelope.data else {
            throw APIError.decoding
        }
        return payload
    }

    /// 不关心返回体的写操作（如保存播放进度、收藏）。
    private func sendIgnoringPayload(url: URL, method: String, body: Data?) async throws {
        let data = try await perform(url: url, method: method, body: body, authorized: true)

        guard let envelope = try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data) else {
            throw APIError.decoding
        }
        guard envelope.success, envelope.code == 200 else {
            throw APIError.server(envelope.message ?? "请求失败（\(envelope.code)）")
        }
    }

    private func perform(url: URL, method: String, body: Data?, authorized: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw APIError.transport("服务器没有返回有效响应")
        }
        try Self.checkStatus(http.statusCode, data: data, decoder: decoder)
        return data
    }

    /// 接口规范 1.4：状态码 → 兜底文案，服务端有 `message` 时优先用服务端的。
    private static func checkStatus(_ code: Int, data: Data, decoder: JSONDecoder) throws {
        if code == 401 || code == 403 {
            let message = (try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data))?.message
            throw APIError.unauthorized(message ?? "登录已失效，请重新登录")
        }
        if code == 404 {
            let message = (try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data))?.message
            throw APIError.notFound(message ?? "")
        }
    }
}
