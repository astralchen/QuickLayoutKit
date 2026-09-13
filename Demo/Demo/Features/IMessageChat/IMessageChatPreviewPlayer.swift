import AVFoundation
import UIKit

/// 统一预览的单实例播放器，参与聊天页的音视频所有权协调。
@available(iOS 26.0, *)
@MainActor
final class IMessageChatPreviewPlayer {
    /// 用于视频图层绑定的当前播放器。
    private(set) var player: AVPlayer?
    /// 播放时间或状态改变后刷新控制层。
    var didChange: (() -> Void)?
    /// 解码或播放失败时通知当前内容页。
    var didFail: (() -> Void)?
    private let coordinator: IMessageChatPlaybackCoordinator
    private let owner = UUID()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var url: URL?
    private var generation = 0
    /// 连续 seek 只接受最新完成回调，避免旧取消回调清除恢复播放意图。
    private var seekGeneration = 0
    private var ownsSession = false
    private(set) var isSeeking = false
    private var resumeAfterSeek = false
    /// UISlider 的弹簧收尾可能在 touch-up 后继续发送 valueChanged。
    private var finishSeekingRequested = false
    /// 当前播放是否有声音；由静音按钮切换。
    var isMuted = false { didSet { player?.isMuted = isMuted; didChange?() } }
    var duration: Double { let value = player?.currentItem?.duration.seconds ?? 0; return value.isFinite ? max(0, value) : 0 }
    var time: Double { let value = player?.currentTime().seconds ?? 0; return value.isFinite ? max(0, value) : 0 }
    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    init(coordinator: IMessageChatPlaybackCoordinator) {
        self.coordinator = coordinator
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    /// 准备原件但不自动播放，也不提前占用音频会话。
    func prepare(url: URL) {
        guard self.url != url || player == nil else { return }
        stop()
        self.url = url
        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        self.player = player
        let generation = generation
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didChange?() }
        }
        statusObserver = player.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                if failed { pause(); didFail?() }
                didChange?()
            }
        }
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.didChange?() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        didChange?()
    }

    /// 取得共享所有权后播放；结束位置从头重播。
    func toggle() {
        if isPlaying { pause(); return }
        guard let player, UIApplication.shared.applicationState != .background else { return }
        coordinator.acquire(owner: owner) { [weak self] in self?.stop() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsSession = true
        } catch { coordinator.release(owner: owner); didFail?(); return }
        if duration > 0, time >= duration - 0.1 { player.seek(to: .zero) }
        player.play()
        didChange?()
    }

    /// 暂停后保留当前位置；回到前台不自动恢复声音。
    func pause() {
        resumeAfterSeek = false
        player?.pause()
        didChange?()
    }

    /// 拖动滑块时冻结周期进度更新并记住原播放状态。
    func beginSeeking() {
        guard !isSeeking else { return }
        isSeeking = true
        finishSeekingRequested = false
        resumeAfterSeek = isPlaying
        player?.pause()
    }

    /// 仅允许当前播放器的 seek 完成回调恢复原播放状态。
    func seek(fraction: Double, finished: Bool) {
        guard let player, duration > 0 else { if finished { isSeeking = false }; return }
        finishSeekingRequested = finishSeekingRequested || finished
        let token = generation
        seekGeneration += 1
        let seekToken = seekGeneration
        let target = CMTime(seconds: min(1, max(0, fraction)) * duration, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self, generation == token, seekGeneration == seekToken, finishSeekingRequested else { return }
                isSeeking = false
                finishSeekingRequested = false
                if completed, resumeAfterSeek, UIApplication.shared.applicationState == .active { self.player?.play() }
                resumeAfterSeek = false
                didChange?()
            }
        }
    }

    /// 释放播放器、观察者及音频会话；迟到回调不能影响下一位所有者。
    func stop() {
        generation += 1
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        rateObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        url = nil
        isSeeking = false
        finishSeekingRequested = false
        resumeAfterSeek = false
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
        coordinator.release(owner: owner)
        didChange?()
    }

    isolated deinit {
        stop()
        for observer in [backgroundObserver, interruptionObserver, routeObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
