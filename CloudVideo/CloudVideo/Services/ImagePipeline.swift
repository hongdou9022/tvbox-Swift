import SwiftUI
import UIKit
import ImageIO

/// 图片加载与缓存。
///
/// 豆瓣海报有防盗链，必须带 Referer 才能取到，所以不能用 `AsyncImage`。
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
        guard !urlString.isEmpty else { return nil }
        return cache.object(forKey: urlString as NSString)
    }

    func load(_ urlString: String) async -> UIImage? {
        guard !urlString.isEmpty else { return nil }
        if let hit = cached(urlString) { return hit }
        guard let url = URL(string: urlString), url.scheme != nil else { return nil }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        // 规范 9.7：豆瓣接口需要 Referer，海报同理
        if let host = url.host, host.contains("douban") {
            request.setValue("https://m.douban.com", forHTTPHeaderField: "Referer")
        } else if let host = url.host {
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

/// 远程图片。占位底色用规范 0.1 的卡片深底 `#1A1B22`（见 9.4）。
struct RemoteImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = Theme.radiusCard

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Theme.cardDeep
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: urlString) {
                if let hit = ImagePipeline.shared.cached(urlString) {
                    image = hit
                    return
                }
                image = nil
                image = await ImagePipeline.shared.load(urlString)
            }
    }
}
