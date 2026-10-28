import SwiftUI

/// 弹幕渲染层。
///
/// 播放器每 0.4 秒回调一次进度，直接用这个粒度画会卡顿，
/// 所以用「最后一次回调时间 + 墙钟增量」做插值，交给 `TimelineView(.animation)` 逐帧绘制。
struct DanmakuOverlay: View {
    @ObservedObject var model: PlayerModel
    let comments: [DanmakuComment]
    var enabled: Bool

    /// 弹幕从右边缘走到左边缘的秒数
    private let travel: Double = 8
    private let laneCount = 6
    private let fontSize: CGFloat = 15

    @State private var anchorTime: Double = 0
    @State private var anchorDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !enabled || !model.isPlaying)) { timeline in
            Canvas { context, size in
                guard enabled, !comments.isEmpty, size.width > 1 else { return }

                let now = anchorTime + (model.isPlaying ? timeline.date.timeIntervalSince(anchorDate) : 0)
                draw(&context, size: size, now: now)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            anchorTime = model.currentTime
            anchorDate = Date()
        }
        .onChange(of: model.currentTime) { _, value in
            anchorTime = value
            anchorDate = Date()
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Double) {
        let windowStart = now - travel
        guard windowStart <= now else { return }

        // comments 按时间升序，二分找到窗口起点，避免每帧遍历全量
        var low = 0
        var high = comments.count
        while low < high {
            let mid = (low + high) / 2
            if comments[mid].time < windowStart {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let laneHeight = min(30, max(20, size.height / CGFloat(laneCount + 3)))
        let topInset = laneHeight * 0.8
        var drawn = 0

        var index = low
        while index < comments.count, drawn < 80 {
            let comment = comments[index]
            index += 1

            guard comment.time <= now else { break }

            let progress = (now - comment.time) / travel
            guard progress >= 0, progress <= 1 else { continue }

            let text = Text(comment.text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(Color(hex: comment.color))

            let resolved = context.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: size.width * 2, height: 40))
            guard textSize.width > 0 else { continue }

            let x = size.width - progress * (size.width + textSize.width)
            guard x > -textSize.width, x < size.width else { continue }

            // 固定泳道，避免上下乱跳
            let lane = index % laneCount
            let y = topInset + CGFloat(lane) * laneHeight

            // 先描一层暗影，保证浅色画面上也看得清
            let shadow = context.resolve(
                Text(comment.text)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
            )
            context.draw(shadow, at: CGPoint(x: x + 1, y: y + 1), anchor: .leading)
            context.draw(resolved, at: CGPoint(x: x, y: y), anchor: .leading)

            drawn += 1
        }
    }
}
