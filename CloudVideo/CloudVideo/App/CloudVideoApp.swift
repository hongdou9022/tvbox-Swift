import SwiftUI
import UIKit

/// 通过 AppDelegate 接管屏幕方向，实现「详情/播放页固定竖屏，仅全屏允许横屏」（规范 9.2）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

@main
struct CloudVideoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore.shared

    init() {
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .onAppear {
                    session.bootstrap()
                }
        }
    }

    private static func configureAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bgHome)

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
