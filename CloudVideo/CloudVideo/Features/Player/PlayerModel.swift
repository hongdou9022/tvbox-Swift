import AVFoundation
import Combine
import UIKit

/// 播放内核。竖屏内联与横屏全屏共用同一个实例，切换时画面不中断。
@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var failed = false

    let player = AVPlayer()

    var onEnd: (() -> Void)?

    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var pendingSeek: Double = 0

    init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
    }

    // MARK: - 观察

    private func observePlayer() {
        let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleTick(time)
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                case .paused:
                    self.isPlaying = false
                @unknown default:
                    break
                }
            }
        }
    }

    private func handleTick(_ time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite, seconds >= 0 {
            currentTime = seconds
        }
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite, itemDuration > 0,
           abs(itemDuration - duration) > 0.5 {
            duration = itemDuration
        }
    }

    // MARK: - 载入

    func load(urlString: String, headers: [String: String], startAt: Double) {
        guard let url = Self.sanitize(urlString) else {
            failed = true
            isBuffering = false
            return
        }

        failed = false
        duration = 0
        currentTime = 0
        isBuffering = true
        pendingSeek = max(0, startAt)

        // 部分源需要 Referer / UA 才能拉到流
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
        let item = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: item)

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status)
            }
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onEnd?()
            }
        }

        play()
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            failed = false
            isBuffering = false

            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }

            if pendingSeek > 1 {
                player.seek(
                    to: CMTime(seconds: pendingSeek, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                currentTime = pendingSeek
            }
            pendingSeek = 0
            play()

        case .failed:
            failed = true
            isBuffering = false

        default:
            break
        }
    }

    // MARK: - 控制

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        Haptics.tap()
    }

    func seek(to seconds: Double) {
        let upper = duration > 0 ? duration : max(seconds, 0.1)
        let target = min(max(seconds, 0), upper)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
    }

    func setRate(_ value: Float) {
        if isPlaying {
            player.rate = value
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    // MARK: - 工具

    static func sanitize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            return url
        }
        return nil
    }
}

/// 轻量触觉反馈。
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
