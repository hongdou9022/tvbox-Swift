import Foundation

/// 应用元信息。
///
/// 规范 1（v1.3 文案要求）：页面标题固定取应用名，**不硬编码**；
/// 全 App 用户可见文案不得出现旧名「OmniBox」。
enum AppInfo {
    /// 取 `CFBundleDisplayName`，取不到时兜底「云影视」。
    static var displayName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "云影视"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
