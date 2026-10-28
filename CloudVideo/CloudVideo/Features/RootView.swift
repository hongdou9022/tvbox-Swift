import SwiftUI

/// 根视图：未配置时进引导页，配置完成后进主 Tab。
struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if app.isConfigured {
                MainTabView()
                    .transition(.opacity)
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.isConfigured)
    }
}

/// 主容器。
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)

            LiveView()
                .tabItem {
                    Label("直播", systemImage: "tv.fill")
                }
                .tag(1)

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(2)

            LibraryView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(3)
        }
        .tint(Theme.accent)
        .onChange(of: selection) { _, _ in
            Haptics.select()
        }
    }
}
