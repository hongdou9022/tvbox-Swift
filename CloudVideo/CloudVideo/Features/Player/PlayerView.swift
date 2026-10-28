import SwiftUI
import AVFoundation
import Combine
import UIKit

// MARK: - 渲染层

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

// MARK: - 进度条（2dp 细线 + 圆点滑块）

struct PlayerProgressBar: View {
    let progress: Double
    var height: CGFloat = 2
    var onScrub: (Double) -> Void
    var onScrubEnd: (Double) -> Void

    @State private var dragging = false
    @State private var dragRatio: Double = 0

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let ratio = dragging ? dragRatio : min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: height)

                Capsule()
                    .fill(Theme.playAccent)
                    .frame(width: max(0, width * ratio), height: height)

                Circle()
                    .fill(Theme.playAccent)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, width * ratio - 5))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        dragRatio = min(max(Double(value.location.x / width), 0), 1)
                        onScrub(dragRatio)
                    }
                    .onEnded { _ in
                        dragging = false
                        onScrubEnd(dragRatio)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - 播放舞台

/// 竖屏内联与横屏全屏共用。控件规格见规范 5.2 / 5.6。
struct PlayerStage: View {
    @ObservedObject var model: PlayerModel

    let title: String
    let episodeName: String
    let qualities: [PlayURLVariant]

    @Binding var isFullscreen: Bool
    @Binding var locked: Bool

    var onBack: () -> Void
    var onCast: () -> Void
    var onQuality: (PlayURLVariant) -> Void
    var onNext: (() -> Void)?
    var onToggleFullscreen: () -> Void
    var onProgress: (Double, Double) -> Void

    /// 弹幕列表，按时间升序。
    var danmaku: [DanmakuComment] = []

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubSeconds: Double = 0
    @State private var danmakuOn = PlayerPreferences.danmakuEnabled
    @State private var rate: Float = 1
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            PlayerSurface(player: model.player)

            // 弹幕层压在画面上、控件之下
            DanmakuOverlay(model: model, comments: danmaku, enabled: danmakuOn)

            // 单击切控件显隐 / 双击播放暂停（规范 5.2 交互）
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.togglePlay()
                    wakeControls(force: true)
                }
                .onTapGesture {
                    toggleControls()
                }

            if model.isBuffering && !model.failed {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            if model.failed {
                failureView
            }

            if controlsVisible && !model.failed {
                controls
                    .transition(.opacity)
            }

            if locked {
                lockOverlay
            }
        }
        .clipped()
        .onAppear {
            wakeControls(force: true)
            model.onEnd = {
                onProgress(model.currentTime, model.duration)
                onNext?()
            }
        }
        .onDisappear {
            onProgress(model.currentTime, model.duration)
            hideTask?.cancel()
        }
        .onReceive(clock) { value in
            now = value
        }
        .onChange(of: model.isPlaying) { _, playing in
            // 规范 5.2：播放中 3 秒自动隐藏控件；暂停时常驻
            if playing {
                scheduleHide()
            } else {
                hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.18)) {
                    controlsVisible = true
                }
            }
        }
    }

    // MARK: - 控件

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if isFullscreen {
                fullscreenBottomBar
            } else {
                portraitBottomBar
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            // 规范 5.1-2 / 5.6：返回 38dp
            CircleIconButton(systemName: "chevron.left", size: 38) {
                onProgress(model.currentTime, model.duration)
                onBack()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if isFullscreen, !episodeName.isEmpty {
                    Text(episodeName)
                        .font(Theme.font(11))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isFullscreen {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(clockText)
                        .font(Theme.font(11))
                }
                .foregroundStyle(Color.white.opacity(0.8))
            }

            CircleIconButton(systemName: "airplayvideo", size: 32) {
                onCast()
            }

            Menu {
                Button("倍速 \(rateText)") { cycleRate() }
                ForEach(qualities, id: \.url) { variant in
                    Button(variant.name ?? "默认") { onQuality(variant) }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, isFullscreen ? 8 : 6)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    /// 规范 5.2：竖屏底部单行。
    private var portraitBottomBar: some View {
        HStack(spacing: 8) {
            Button {
                model.togglePlay()
                wakeControls(force: true)
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Text(timeText(scrubbing ? scrubSeconds : model.currentTime))
                .font(Theme.font(11))
                .foregroundStyle(.white)
                .frame(width: 40)

            PlayerProgressBar(
                progress: progressRatio,
                onScrub: { ratio in
                    scrubbing = true
                    scrubSeconds = ratio * max(model.duration, 1)
                },
                onScrubEnd: { ratio in
                    model.seek(to: ratio * max(model.duration, 1))
                    scrubbing = false
                    onProgress(model.currentTime, model.duration)
                }
            )

            Text(timeText(model.duration))
                .font(Theme.font(11))
                .foregroundStyle(.white)
                .frame(width: 40)

            Menu {
                ForEach(qualities, id: \.url) { variant in
                    Button(variant.name ?? "默认") { onQuality(variant) }
                }
            } label: {
                Text(qualityText)
                    .font(Theme.font(12))
                    .foregroundStyle(.white)
                    .frame(minWidth: 30)
            }

            Button {
                danmakuOn.toggle()
            } label: {
                Text("弹")
                    .font(Theme.font(12))
                    .foregroundStyle(danmakuOn ? Theme.danmakuOn : Theme.danmakuOff)
            }
            .buttonStyle(.plain)

            Button {
                onToggleFullscreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        )
    }

    /// 规范 5.6：横屏底部两行。
    private var fullscreenBottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(timeText(scrubbing ? scrubSeconds : model.currentTime))
                    .font(Theme.font(11))
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .leading)

                PlayerProgressBar(
                    progress: progressRatio,
                    height: 3,
                    onScrub: { ratio in
                        scrubbing = true
                        scrubSeconds = ratio * max(model.duration, 1)
                    },
                    onScrubEnd: { ratio in
                        model.seek(to: ratio * max(model.duration, 1))
                        scrubbing = false
                        onProgress(model.currentTime, model.duration)
                    }
                )

                Text(timeText(model.duration))
                    .font(Theme.font(11))
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 20) {
                Button {
                    model.togglePlay()
                    wakeControls(force: true)
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)

                if let onNext {
                    Button(action: onNext) {
                        HStack(spacing: 4) {
                            Text("下一集")
                                .font(Theme.font(12))
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    danmakuOn.toggle()
                } label: {
                    Text("弹")
                        .font(Theme.font(12))
                        .foregroundStyle(danmakuOn ? Theme.danmakuOn : Theme.danmakuOff)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text("换源")
                    .font(Theme.font(12))
                    .foregroundStyle(.white)

                Menu {
                    ForEach(qualities, id: \.url) { variant in
                        Button(variant.name ?? "默认") { onQuality(variant) }
                    }
                } label: {
                    Text(qualityText)
                        .font(Theme.font(12))
                        .foregroundStyle(.white)
                }

                Button {
                    cycleRate()
                } label: {
                    Text(rateText)
                        .font(Theme.font(12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text("选集")
                    .font(Theme.font(12))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
        )
    }

    /// 规范 5.6：左侧边缘锁屏按钮。
    private var lockOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    locked = false
                    wakeControls(force: true)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                Spacer()
            }
            Spacer()
        }
    }

    private var failureView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.playAccent)
            Text("这个片源播不了")
                .font(Theme.font(13, .semibold))
                .foregroundStyle(.white)
            Text("换一条线路或换源试试")
                .font(Theme.font(11))
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    // MARK: - 状态

    private var progressRatio: Double {
        guard model.duration > 0 else { return 0 }
        let seconds = scrubbing ? scrubSeconds : model.currentTime
        return min(max(seconds / model.duration, 0), 1)
    }

    private var qualityText: String {
        qualities.first?.name ?? "自动"
    }

    private var rateText: String {
        rate == 1 ? "倍速" : String(format: "%.2gx", rate)
    }

    private var clockText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: now)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func cycleRate() {
        let rates: [Float] = [1, 1.25, 1.5, 2]
        let index = rates.firstIndex(of: rate) ?? 0
        rate = rates[(index + 1) % rates.count]
        model.setRate(rate)
    }

    // MARK: - 控件显隐

    private func toggleControls() {
        guard !locked else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func wakeControls(force: Bool = false) {
        if force || !controlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                controlsVisible = true
            }
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard model.isPlaying, !locked else { return }

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                controlsVisible = false
            }
        }
    }
}
