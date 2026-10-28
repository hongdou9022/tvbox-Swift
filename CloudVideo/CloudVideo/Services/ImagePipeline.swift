import SwiftUI
import UIKit
import ImageIO

/// 图片加载与缓存。
///
/// 不用 `AsyncImage` 的原因：大量资源站的图片有防盗链，必须带 Referer / UA 才能取到，
/// 而 `AsyncImage` 不支持自定义请求头，海报会整片加载不出来。
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 80 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func cached(_ urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func load(_ urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else { return nil }
        if let hit = cached(urlString) { return hit }
        guard let url = Self.resolve(urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        if let host = url.host {
            request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = Self.downsample(data: data, maxPixel: 640) else { return nil }
            cache.setObject(image, forKey: urlString as NSString, cost: data.count)
            return image
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
    }

    /// 统一处理海报地址：补协议、修正已知防盗链域名。
    static func resolve(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("//") {
            text = "https:" + text
        }
        guard text.hasPrefix("http") else { return nil }

        return URL(string: text)
    }

    /// 解码时直接生成缩略图，避免大图占满内存。
    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }
}

/// 通用远程图片视图，带占位与失败态。
struct RemoteImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        // 用 Color.clear 当尺寸基准：它会严格接受父级给的尺寸，
        // 图片再在 overlay 里铺满并裁剪，避免 .fill 撑破卡片。
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Theme.panelHigh
                        .overlay(
                            Image(systemName: failed ? "photo" : "film")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(Theme.textTertiary)
                        )
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: urlString) {
                failed = false
                if let hit = ImagePipeline.shared.cached(urlString) {
                    image = hit
                    return
                }
                image = nil
                let loaded = await ImagePipeline.shared.load(urlString)
                image = loaded
                failed = loaded == nil
            }
    }
}
