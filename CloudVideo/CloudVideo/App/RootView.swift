import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isLoggedIn)
        .onAppear {
            OrientationLock.portrait()
        }
    }
}

/// 规范 2：底部四个 tab —— 首页 / 电视 / 直播 / 我的，选中为绿色。
struct MainTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            TVView()
                .tabItem { Label("电视", systemImage: "tv.fill") }
                .tag(1)

            LiveView()
                .tabItem { Label("直播", systemImage: "dot.radiowaves.left.and.right") }
                .tag(2)

            MineView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
    }
}
