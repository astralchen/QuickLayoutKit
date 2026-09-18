import Foundation
import OSLog
import UIKit

/// 为单项礼物效果提供异步播放和同步停止接口。
///
/// 所有调用均在主执行器上进行。具体实现负责将底层播放器事件转换为一次播放结果。
@MainActor
protocol GiftEffectPlaying: AnyObject {
    /// 播放一个明确配置的礼物效果，并等待该效果完成。
    ///
    /// 返回或抛出错误前应清理画面。任务取消时，实现必须停止底层工作并结束等待。
    ///
    /// - Parameters:
    ///   - effect: 本次需要执行的单项特效配置。
    ///   - gift: 用于图标、文案和配色的礼物数据。
    ///   - quantity: 向每名收礼人赠送的份数。
    /// - Throws: 播放失败或任务取消时的错误。
    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws
    /// 同步停止加载、播放及事件监听，并移除当前效果。
    ///
    /// 实现必须允许重复调用；若仍有调用等待播放结果，应结束该等待。
    func stop()
}

/// 将每份礼物的完整效果序列提交给串行任务队列的协调器。
///
/// 一次赠送占用一个队列任务，组内效果不会与后续赠送交错。播放器创建和清理由播放序列负责。
@MainActor
final class GiftMainEffectCoordinator {
    /// 通用调度器只运行调用方提交的闭包，不依赖 Gift 或播放器。
    private let queue = SerialTaskQueue()
    /// 与播放独立调度的资源预热器；仅服务已确认入队的赠送。
    private let prefetcher: GiftEffectPrefetcher
    /// 一个布尔值，指示是否接受新的主特效请求；初始值为 `false`。
    private(set) var isActive = false
    /// 尚未开始执行的赠送请求数量，不包含当前任务。
    var pendingCount: Int { queue.pendingCount }
    /// 一个布尔值，指示队列当前是否仍有任务执行，包括取消后的退出阶段。
    var isPlaying: Bool { queue.isRunning }
    /// 整组实际开始后的协作式超时期限定，不包含排队时间。
    private let timeout: TimeInterval
    /// 当前效果开始时才创建播放器，预下载不持有视图。
    private let makePlayer: @MainActor () -> any GiftEffectPlaying
    /// 入队和整组开始时读取；减少动态效果不预下载，只展示一次静态礼物。
    private let reduceMotionEnabled: @MainActor () -> Bool
    /// 展示错误仅用于诊断，不影响已成功的赠送业务。
    private let logger = Logger(subsystem: "Demo.VoiceRoom", category: "GiftPlayback")

    /// 创建具有指定超时和播放器工厂的礼物播放协调器。
    ///
    /// - Parameters:
    ///   - timeout: 整组任务实际开始后的协作式超时时长，单位为秒，默认值为 `60`；不含排队时间。
    ///   - reduceMotionEnabled: 在入队和整组开始时读取的减少动态效果设置；默认读取系统值。
    ///   - prefetcher: 预下载调度器，默认复用 VAP/SVGA 缓存；测试可替换加载器。
    ///   - makePlayer: 当前效果实际开始时创建远程或静态展示播放器的工厂。
    init(timeout: TimeInterval = 60, reduceMotionEnabled: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }, prefetcher: GiftEffectPrefetcher = GiftEffectPrefetcher(), makePlayer: @escaping @MainActor () -> any GiftEffectPlaying) {
        self.timeout = timeout
        self.makePlayer = makePlayer
        self.reduceMotionEnabled = reduceMotionEnabled
        self.prefetcher = prefetcher
    }

    isolated deinit {
        queue.cancelAll()
        prefetcher.cancelAll()
    }

    /// 允许接收后续赠送的主特效请求；不会恢复已取消的请求。
    func activate() { isActive = true }

    /// 将一份赠送的完整效果序列加入串行队列。
    ///
    /// 队列等待时间不计入播放超时。播放失败仅影响展示，不回滚已确认的赠送；取消后须等待当前任务退出才开始后续任务。
    ///
    /// - Parameters:
    ///   - gift: 包含有序特效配置的礼物。
    ///   - quantity: 向每名收礼人赠送的份数。
    ///   - makeNativePlayer: 创建原生效果播放器的工厂；包含原生项时应提供。
    /// - Returns: 可用于等待或取消的任务句柄；未激活或效果列表为空时为 `nil`。
    @discardableResult
    func enqueue(gift: Gift, quantity: Int, makeNativePlayer: (@MainActor () -> any GiftEffectPlaying)? = nil) -> Task<Void, Error>? {
        guard isActive, !gift.effects.isEmpty else { return nil }
        // 先登记预下载，再提交串行播放；前一份礼物播放期间即可准备后续资源。
        let requestID = reduceMotionEnabled() ? nil : prefetcher.register(effects: gift.effects)
        let sequence = GiftEffectSequence(makePlayer: makePlayer, makeNativePlayer: makeNativePlayer)
        let task = queue.addTask { [reduceMotionEnabled, timeout, logger, prefetcher] in
            defer { if let requestID { prefetcher.release(requestID) } }
            do {
                // 排队期间系统设置可能改变；开始播放时再次检查，并释放不再需要的远程资源。
                let reducedMotion = reduceMotionEnabled()
                if reducedMotion, let requestID { prefetcher.release(requestID) }
                let play: @MainActor () async throws -> Void = {
                    try await sequence.play(gift: gift, quantity: quantity, reducedMotion: reducedMotion)
                }
                if #available(iOS 16.0, *) {
                    try await withTaskTimeout(for: .seconds(timeout), operation: play)
                } else {
                    try await withTaskTimeout(seconds: timeout, operation: play)
                }
            } catch {
                if !(error is CancellationError) {
                    logger.error("礼物主特效展示失败：\(error.localizedDescription, privacy: .public)")
                }
                throw error
            }
        }
        // 等待项取消时不会进入上面的操作体，必须独立观察句柄的终态。
        if let requestID {
            Task { [weak prefetcher] in
                _ = await task.result
                prefetcher?.release(requestID)
            }
        }
        return task
    }

    /// 停止接收新请求，并取消当前及待执行的任务。
    ///
    /// 当前任务实际返回或抛出错误后才释放串行执行槽。此方法可以重复调用。
    func deactivate() {
        isActive = false
        prefetcher.cancelAll()
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
