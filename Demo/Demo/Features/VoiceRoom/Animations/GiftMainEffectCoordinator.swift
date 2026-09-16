import Foundation
import OSLog
import UIKit

/// 统一异步特效播放边界；SDK 回调只留在具体适配器内部。
@MainActor
protocol GiftEffectPlaying: AnyObject {
    /// 等待一个明确配置的效果完成；任务取消必须停止底层工作并结束等待，返回前清理画面。
    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws
    /// 取消加载、播放与事件监听，并移除画面；允许重复调用。
    func stop()
}

/// 将礼物播放行为提交给通用队列；不实现排队、计时或终态去重。
@MainActor
final class GiftMainEffectCoordinator {
    /// 通用调度器只运行调用方提交的闭包，不依赖 Gift 或播放器。
    private let queue = SerialTaskQueue()
    /// 当前房间是否可接受新的主特效。
    private(set) var isActive = false
    /// 等待播放的赠送请求数。
    var pendingCount: Int { queue.pendingCount }
    /// 是否正在加载或播放主特效。
    var isPlaying: Bool { queue.isRunning }
    /// 整组实际开始后的协作式超时期限定，不包含排队时间。
    private let timeout: TimeInterval
    /// 当前任务开始时才创建播放器，不预先加载等待项资源。
    private let makePlayer: @MainActor () -> any GiftEffectPlaying
    /// 整组开始时读取；减少动态效果只展示一次静态礼物，不执行组合中的素材。
    private let reduceMotionEnabled: @MainActor () -> Bool
    /// 展示错误仅用于诊断，不影响已成功的赠送业务。
    private let logger = Logger(subsystem: "Demo.VoiceRoom", category: "GiftPlayback")

    /// 由礼物使用方指定 60 秒超时；其他业务可采用自己的队列和时间策略。
    init(timeout: TimeInterval = 60, reduceMotionEnabled: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }, makePlayer: @escaping @MainActor () -> any GiftEffectPlaying) {
        self.timeout = timeout
        self.makePlayer = makePlayer
        self.reduceMotionEnabled = reduceMotionEnabled
    }

    /// 页面可见时允许新的赠送展示。
    func activate() { isActive = true }

    /// 提交一份赠送并返回原生任务句柄；页面关闭接收或配置为空时返回 nil。
    @discardableResult
    func enqueue(gift: Gift, quantity: Int, makeNativePlayer: (@MainActor () -> any GiftEffectPlaying)? = nil) -> Task<Void, Error>? {
        guard isActive, !gift.effects.isEmpty else { return nil }
        let sequence = GiftEffectSequence(makePlayer: makePlayer, makeNativePlayer: makeNativePlayer)
        return queue.addTask { [reduceMotionEnabled, timeout, logger] in
            do {
                try await withTimeout(timeout) {
                    try await sequence.play(gift: gift, quantity: quantity, reducedMotion: reduceMotionEnabled())
                }
            } catch {
                if !(error is CancellationError) {
                    logger.error("礼物主特效展示失败：\(error.localizedDescription, privacy: .public)")
                }
                throw error
            }
        }
    }

    /// 关闭接收并请求取消；播放器退出后才释放执行槽，重新激活不恢复旧请求。
    func deactivate() {
        isActive = false
        queue.cancelAll()
    }
}

/// 展示层错误，不代表赠送业务失败。
enum GiftMainEffectPlaybackError: LocalizedError {
    /// 页面容器或主特效配置已经不可用。
    case unavailable
    /// 播放器在自然完成前停止。
    case stopped

    /// 用于诊断日志的中文错误说明。
    var errorDescription: String? {
        switch self {
        case .unavailable: "主特效容器或配置不可用"
        case .stopped: "主特效播放提前停止"
        }
    }
}
