import SwiftUI

/// 直播 Tab（规范第 6 章）：IPTV 频道分组 + 直播间。
struct LiveView: View {
    @State private var groups: [String] = []
    @State private var selectedGroup: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .homeBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("直播")
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.textPrimary)

            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups, id: \.self) { group in
                            Button {
                                selectedGroup = group
                            } label: {
                                ChipView(title: group, selected: selectedGroup == group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.padPage)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()
            EmptyHintView(
                icon: "dot.radiowaves.left.and.right",
                text: "还没有直播源。\n在服务端添加 IPTV 订阅后，频道会出现在这里。"
            )
            Spacer()
        }
    }
}
