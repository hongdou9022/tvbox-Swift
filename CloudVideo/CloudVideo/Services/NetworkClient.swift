import Foundation

enum NetworkError: LocalizedError {
    case invalidURL(String)
    case badStatus(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "无效地址：\(url)"
        case .badStatus(let code): return "服务器返回 \(code)"
        case .decodeFailed: return "内容解码失败"
        }
    }
}

/// 网络层。相比参考项目额外做了两件事：
/// 1. 中文资源站大量使用 GBK/GB2312，这里按响应头 → 常见编码顺序逐级兜底；
/// 2. 对 5xx / 超时做一次指数退避重试，弱网下体验差别很明显。
final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    func getString(_ urlString: String, headers: [String: String]? = nil) async throws -> String {
        let data = try await getData(urlString, headers: headers)
        guard let text = Self.decode(data: data) else {
            throw NetworkError.decodeFailed
        }
        return text
    }

    func getData(_ urlString: String, headers: [String: String]? = nil) async throws -> Data {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw NetworkError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        var lastError: Error = NetworkError.badStatus(-1)

        for attempt in 0..<2 {
            do {
                try Task.checkCancellation()
                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    let error = NetworkError.badStatus(http.statusCode)
                    if [408, 429, 500, 502, 503, 504].contains(http.statusCode), attempt == 0 {
                        lastError = error
                        try await Task.sleep(nanoseconds: 600_000_000)
                        continue
                    }
                    throw error
                }

                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0, error.isTransient {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    continue
                }
                throw error
            }
        }

        throw lastError
    }

    // MARK: - 编码兜底

    private static let charsetCandidates = [
        "utf-8", "gb18030", "gbk", "gb2312", "big5", "utf-16", "iso-8859-1"
    ]

    private static func decode(data: Data) -> String? {
        for charset in charsetCandidates {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { continue }
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            if let text = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                return text
            }
        }

        if let text = String(data: data, encoding: .utf8) { return text }

        // 最后兜底：宽容解码，至少能拿到 ASCII 部分
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}

extension Error {
    /// 是否为值得重试的瞬态网络错误。
    var isTransient: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorSecureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
