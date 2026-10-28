import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - 视频渲染层

/// 用 AVPlayerLayer 而不是 `VideoPlayer`：后者自带一套系统控件，
/// 无法和自定义手势层、自定义控制条共存。
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
        // layerClass 已声明为 AVPlayerLayer，这里不会失败
        layer as! AVPlayerLayer
    }
}

// MARK: - 系统音量

/// `AVAudioSession.outputVolume` 是只读的，改音量必须借 MPVolumeView 内部的 UISlider。
/// 所以需要把这个 1x1 的视图放进视图层级里，滑块才生效。
final class VolumeBridge {
    static weak var volumeView: MPVolumeView?

    static var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    static var current: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    static func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        DispatchQueue.main.async {
            slider?.value = clamped
        }
    }
}

struct VolumeSliderView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsRouteButton = false
        view.alpha = 0.01
        VolumeBridge.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        VolumeBridge.volumeView = uiView
    }
}

// MARK: - 播放器

struct PlayerView: View {
    let title: String
    var subtitle: String = ""
    let urlString: String
    var startAt: Double = 0
    var hasNext: Bool = false

    var onClose: () -> Void
    var onProgress: (Double, Double) -> Void = { _, _ in }
    var onFinished: () -> Void = {}
    var onNext: () -> Void = {}

    @StateObject private var model = PlayerModel()

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hudText: String?
    @State private var brightness: CGFloat = UIScreen.main.brightness
    @State private var dragMode: DragMode = .none
    @State private var dragStartTime: Double = 0
    @State private var dragStartValue: CGFloat = 0
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var rateIndex = 0

    private let rates: [Float] = [1.0, 1.25, 1.5, 2.0]

    private enum DragMode {
        case none, seek, brightness, volume
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerSurface(player: model.player)
                    .scaleEffect(zoom)
                    .ignoresSafeArea()

                // 隐藏但必须在层级里，否则调音量无效
                VolumeSliderView()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                gestureLayer(size: geo.size)

                if model.isBuffering && !model.failed {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                }

                if model.failed {
                    failureView
                }

                if controlsVisible && !model.failed {
                    controls(size: geo.size)
                        .transition(.opacity)
                }

                if let hudText {
                    hudView(hudText)
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            model.onEnd = {
                // 播完先把进度落盘，再决定是否自动下一集
                onProgress(model.currentTime, model.duration)
                onFinished()
            }
            model.load(urlString: urlString, startAt: startAt)
            scheduleHide()
        }
        .onDisappear {
            onProgress(model.currentTime, model.duration)
            model.stop()
            hideTask?.cancel()
        }
    }

    // MARK: - 手势层

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size))
            .simultaneousGesture(tapGesture(size: size))
            .simultaneousGesture(zoomGesture)
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        let double = SpatialTapGesture(count: 2).onEnded { value in
            handleDoubleTap(at: value.location, size: size)
        }
        let single = SpatialTapGesture(count: 1).onEnded { _ in
            toggleControls()
        }
        return double.exclusively(before: single)
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                handleDrag(value, size: size)
            }
            .onEnded { _ in
                endDrag()
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(baseZoom * value, 1), 3)
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }

    private func handleDoubleTap(at location: CGPoint, size: CGSize) {
        if location.x < size.width / 3 {
            seekBy(-10)
            showHUD("后退 10 秒")
        } else if location.x > size.width * 2 / 3 {
            seekBy(10)
            showHUD("前进 10 秒")
        } else {
            model.togglePlay()
            showHUD(model.isPlaying ? "播放" : "暂停")
        }
        scheduleHide()
    }

    private func handleDrag(_ value: DragGesture.Value, size: CGSize) {
        if dragMode == .none {
            if abs(value.translation.width) > abs(value.translation.height) {
                dragMode = .seek
                dragStartTime = model.currentTime
                scrubbing = true
                scrubValue = model.currentTime
            } else {
                dragMode = value.startLocation.x < size.width / 2 ? .brightness : .volume
                dragStartValue = dragMode == .brightness ? brightness : CGFloat(VolumeBridge.current)
            }
        }

        switch dragMode {
        case .seek:
            let delta = Double(value.translation.width) / 6.0
            let upper = model.duration > 0 ? model.duration : 0
            let target = min(max(dragStartTime + delta, 0), upper)
            scrubValue = target
            hudText = "\(timeText(target)) / \(timeText(model.duration))"

        case .brightness:
            let next = min(max(dragStartValue - value.translation.height / 220, 0), 1)
            brightness = next
            UIScreen.main.brightness = next
            hudText = "亮度 \(Int(next * 100))%"

        case .volume:
            let next = min(max(dragStartValue - value.translation.height / 220, 0), 1)
            VolumeBridge.set(Float(next))
            hudText = "音量 \(Int(next * 100))%"

        case .none:
            break
        }
    }

    private func endDrag() {
        if dragMode == .seek {
            model.seek(to: scrubValue)
            scrubbing = false
            onProgress(model.currentTime, model.duration)
        }
        dragMode = .none
        hudText = nil
        scheduleHide()
    }

    // MARK: - 控制条

    private func controls(size: CGSize) -> some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    onProgress(model.currentTime, model.duration)
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            HStack(spacing: 40) {
                Button {
                    seekBy(-15)
                    showHUD("后退 15 秒")
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 25))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    model.togglePlay()
                    showHUD(model.isPlaying ? "暂停" : "播放")
                    scheduleHide()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)

                Button {
                    seekBy(15)
                    showHUD("前进 15 秒")
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 25))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(timeText(scrubbing ? scrubValue : model.currentTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 54, alignment: .leading)

                    Slider(
                        value: sliderBinding,
                        in: 0...max(model.duration, 1),
                        onEditingChanged: handleSliderEditing
                    )
                    .tint(Theme.accent)

                    Text(timeText(model.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 54, alignment: .trailing)
                }

                HStack(spacing: 14) {
                    Button {
                        cycleRate()
                    } label: {
                        Text(rateLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if hasNext {
                        Button {
                            onProgress(model.currentTime, model.duration)
                            onNext()
                        } label: {
                            HStack(spacing: 5) {
                                Text("下一集")
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { scrubbing ? scrubValue : model.currentTime },
            set: { scrubValue = $0 }
        )
    }

    private func handleSliderEditing(_ editing: Bool) {
        if editing {
            scrubbing = true
            scrubValue = model.currentTime
            hideTask?.cancel()
        } else {
            model.seek(to: scrubValue)
            scrubbing = false
            onProgress(model.currentTime, model.duration)
            scheduleHide()
        }
    }

    private var rateLabel: String {
        let value = rates[rateIndex]
        return value == 1.0 ? "倍速" : String(format: "%.2gx", value)
    }

    private func cycleRate() {
        rateIndex = (rateIndex + 1) % rates.count
        model.setRate(rates[rateIndex])
        Haptics.tap()
        showHUD(rateIndex == 0 ? "正常速度" : rateLabel)
    }

    // MARK: - HUD

    private func hudView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color.black.opacity(0.6))
            )
            .padding(.bottom, 90)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
    }

    private func showHUD(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            hudText = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                if hudText == text { hudText = nil }
            }
        }
    }

    // MARK: - 失败态

    private var failureView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.gold)

            Text("这个片源播不了")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("可以回到详情页换一条线路再试")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.55))

            HStack(spacing: 12) {
                Button {
                    model.load(urlString: urlString, startAt: startAt)
                } label: {
                    Text("重试")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onClose()
                } label: {
                    Text("返回")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 工具

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }

    private func seekBy(_ offset: Double) {
        model.seek(to: model.currentTime + offset)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
