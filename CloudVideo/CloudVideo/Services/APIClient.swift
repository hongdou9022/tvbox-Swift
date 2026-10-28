import Foundation

enum APIError: LocalizedError {
    case badAddress
    case unauthorized(String)
    case server(String)
    case decoding
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badAddress:
            return "服务器地址格式不正确"
        case .unauthorized(let message):
            return message.isEmpty ? "用户名或密码错误" : message
        case .server(let message):
            return message
        case .decoding:
            return "服务器返回的数据无法解析"
        case .transport(let message):
            return message
        }
    }
}

/// 对接后端 `internal/routes/app.go` 定义的第一方客户端接口。
///
/// 统一约定：
/// - 除登录外全部需要 `Authorization: Bearer <token>`
/// - 响应体统一为 `{code, message, data, success}`
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
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
    }

    // MARK: - 会话

    /// 规范 1：地址允许不带协议，自动补 `http://`，末尾 `/` 自动去掉。
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

    // MARK: - 详情与播放

    func media(libraryId: String, videoId: String, sourceType: String) async throws -> MediaDetail {
        try await get("api/app/v1/media", query: [
            URLQueryItem(name: "libraryId", value: libraryId),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "sourceType", value: sourceType)
        ])
    }

    func play(libraryId: String, videoId: String, line: Int, episode: Int, sourceType: String) async throws -> PlayInfo {
        try await get("api/app/v1/play", query: [
            URLQueryItem(name: "libraryId", value: libraryId),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "line", value: "\(line)"),
            URLQueryItem(name: "episode", value: "\(episode)"),
            URLQueryItem(name: "sourceType", value: sourceType)
        ])
    }

    // MARK: - 续播与进度

    func resume(limit: Int = 12) async throws -> [ResumeItem] {
        try await get("api/app/v1/resume", query: [
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
    }

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

    // MARK: - 搜索

    func search(keyword: String, page: Int, sourceId: String? = nil) async throws -> SearchPage {
        var items = [
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if let sourceId, !sourceId.isEmpty {
            items.append(URLQueryItem(name: "sourceId", value: sourceId))
        }
        return try await get("api/app/v1/search", query: items)
    }

    func searchSources() async throws -> [SearchSource] {
        try await get("api/app/v1/search-sources")
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
            "rating": rating
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

    func pairDevice(deviceId: String, pairToken: String, phoneId: String, phoneName: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "pairToken": pairToken,
            "phoneId": phoneId,
            "phoneName": phoneName
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

    // MARK: - 直播

    func iptvSources() async throws -> [IPTVSource] {
        try await get("api/iptv/enabled")
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
        return envelope.data ?? []
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
        try await send(url: try endpoint(path, query: query), method: "GET", body: nil)
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

    /// 不关心返回体的写操作（如保存播放进度）。
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

        if http.statusCode == 401 {
            let message = (try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data))?.message
            throw APIError.unauthorized(message ?? "登录已过期，请重新登录")
        }
        return data
    }
}
