import AppLocalization
import SVGAView
import UIKit
import VAPView

/// 将两种播放器的事件统一为一次展示的终态；动画文件仅由库运行时缓存。
@MainActor
final class GiftMainEffectPlayer: GiftEffectPlaying {
    /// 页面拥有容器，播放器不延长页面生命周期。
    private weak var containerView: UIView?
    /// 当前 VAP 播放器，停止后销毁解码与渲染资源。
    private var vapView: VAPView?
    /// 当前 SVGA 播放器，停止后取消加载并清空画布。
    private var svgaView: SVGAView?
    /// 减少动态效果时的静态展示容器。
    private var reducedMotionView: UIView?
    /// SDK 回调转换为异步结果；每次调用拥有独立身份和资源清理。
    private let playback = GiftPlaybackOperation()
    /// SVGA 自然结束会先发 stopped，再发 finished；延迟判定可区分异常停止。
    private var stoppedEventTask: Task<Void, Never>?
    /// 查询时机在当前项开始播放时，避免预先下载不可展示的素材。
    private let reduceMotionEnabled: @MainActor () -> Bool

    /// 创建不触发下载的适配器。
    init(containerView: UIView, reduceMotionEnabled: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.containerView = containerView
        self.reduceMotionEnabled = reduceMotionEnabled
    }

    /// 异步等待当前配置，远程 URL 只在此时交给对应库，显式播放一遍。
    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws {
        try await playback.run { [weak self] completion in
            guard let self, let containerView = self.containerView else {
                completion(.failure(GiftMainEffectPlaybackError.unavailable))
                return {}
            }
            self.start(effect: effect, gift: gift, quantity: quantity, in: containerView, completion: completion)
            return { [weak self] in self?.releaseResources() }
        }
    }

    /// 启动具体 SDK；结果回调属于本次播放，不能读取复用后的新完成状态。
    private func start(effect: GiftEffect, gift: Gift, quantity: Int, in containerView: UIView, completion: @escaping GiftPlaybackOperation.Completion) {
        if reduceMotionEnabled() {
            showReducedMotion(gift: gift, quantity: quantity, in: containerView, completion: completion)
            return
        }
        switch effect {
        case .native:
            completion(.failure(GiftMainEffectPlaybackError.unavailable))
        case .vap(let url):
            let view = VAPView(frame: containerView.bounds)
            vapView = view
            attach(view, to: containerView, identifier: "liveRoom.gift.effect.vap")
            view.automaticallyDestroysPlayerAfterPlayback = true
            view.play(VAPPlaybackConfiguration(
                source: url.absoluteString, backgroundPolicy: .stop,
                contentMode: .aspectFill, loopCount: 1
            )) { event in
                switch event {
                case .didFinish:
                    completion(.success(()))
                case .didFail(let error):
                    completion(.failure(error))
                case .didStop:
                    completion(.failure(GiftMainEffectPlaybackError.stopped))
                default: break
                }
            }
        case .svga(let url):
            let view = SVGAView(frame: containerView.bounds)
            svgaView = view
            attach(view, to: containerView, identifier: "liveRoom.gift.effect.svga")
            view.contentMode = .scaleAspectFill
            view.loops = 1
            view.clearsAfterStop = true
            view.onEvent = { [weak self, weak view] event in
                guard let self, let view, self.svgaView === view else { return }
                switch event {
                case .finished:
                    completion(.success(()))
                case .loadFailed(let error):
                    completion(.failure(error))
                case .stateChanged(.stopped):
                    self.scheduleStoppedEvent(completion: completion)
                default: break
                }
            }
            view.play(remoteURL: url)
        }
    }

    /// 先撤销回调再停止播放器，避免主动清理被误判为下一项的终态。
    func stop() { playback.stop() }

    /// 撤销 SDK 监听并释放渲染资源；在恢复异步等待之前同步执行。
    private func releaseResources() {
        stoppedEventTask?.cancel()
        stoppedEventTask = nil
        vapView?.stop()
        vapView?.removeFromSuperview()
        vapView = nil
        svgaView?.onEvent = nil
        svgaView?.clear()
        svgaView?.removeFromSuperview()
        svgaView = nil
        reducedMotionView?.layer.removeAllAnimations()
        reducedMotionView?.removeFromSuperview()
        reducedMotionView = nil
    }

    /// 给同一事件栈内的 finished 优先权；主动取消会撤销此判定。
    private func scheduleStoppedEvent(completion: @escaping GiftPlaybackOperation.Completion) {
        stoppedEventTask?.cancel()
        stoppedEventTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            completion(.failure(GiftMainEffectPlaybackError.stopped))
        }
    }

    /// 铺满现有特效容器，保持透明与点击穿透，并随容器尺寸变化。
    private func attach(_ view: UIView, to container: UIView, identifier: String) {
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.accessibilityIdentifier = identifier
        container.addSubview(view)
    }

    /// 不创建远程播放器，以图标和数量完成短暂淡入淡出展示。
    private func showReducedMotion(gift: Gift, quantity: Int, in container: UIView, completion: @escaping GiftPlaybackOperation.Completion) {
        let overlay = UIView(frame: container.bounds)
        reducedMotionView = overlay
        attach(overlay, to: container, identifier: "liveRoom.gift.effect.reducedMotion")
        let image = UIImageView(image: UIImage(systemName: gift.symbolName))
        image.contentMode = .scaleAspectFit
        image.tintColor = VoiceRoomTheme.giftColor(at: gift.themeIndex)
        let label = UILabel()
        label.text = "\(gift.localizedTitle) ×\(quantity)"
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [image, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            image.heightAnchor.constraint(equalToConstant: 64),
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.8),
        ])
        overlay.alpha = 0
        UIView.animateKeyframes(withDuration: 0.6, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) { overlay.alpha = 1 }
            UIView.addKeyframe(withRelativeStartTime: 0.75, relativeDuration: 0.25) { overlay.alpha = 0 }
        } completion: { finished in
            guard finished else { return }
            Task { @MainActor in completion(.success(())) }
        }
    }
}
