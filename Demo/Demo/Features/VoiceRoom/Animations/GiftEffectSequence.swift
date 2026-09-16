import Foundation
import OSLog

/// 按配置顺序完成一份赠送中所有效果的播放对象。
///
/// 每一项完成并清理后才开始下一项；整个序列作为一个任务交给外部队列调度。
@MainActor
final class GiftEffectSequence {
    /// 远程或减少动态效果的播放器工厂，轮到当前效果时才创建。
    private let makePlayer: @MainActor () -> any GiftEffectPlaying
    /// 原生播放器工厂，包含本次收礼人的坐标解析上下文。
    private let makeNativePlayer: (@MainActor () -> any GiftEffectPlaying)?
    /// 逐项记录展示错误，避免后续效果失败被整组首个错误遮蔽。
    private let logger = Logger(subsystem: "Demo.VoiceRoom", category: "GiftEffectSequence")

    /// 保存播放工厂，不创建播放器或加载素材；每份赠送使用独立实例。
    init(makePlayer: @escaping @MainActor () -> any GiftEffectPlaying, makeNativePlayer: (@MainActor () -> any GiftEffectPlaying)?) {
        self.makePlayer = makePlayer
        self.makeNativePlayer = makeNativePlayer
    }

    /// 按配置顺序播放礼物效果，并在整组结束时报告首个展示错误。
    ///
    /// 普通播放错误不会阻止后续项，任务取消会立即停止继续迭代。减少动态效果时只使用第一项配置执行一次静态展示。
    ///
    /// - Parameters:
    ///   - gift: 提供有序效果列表和显示内容的礼物。
    ///   - quantity: 向每名收礼人赠送的份数。
    ///   - reducedMotion: 是否只展示一次简化的静态效果。
    /// - Throws: 任务取消错误，或整组播放中遇到的首个非取消错误。
    func play(gift: Gift, quantity: Int, reducedMotion: Bool) async throws {
        var firstError: Error?
        let effects = reducedMotion ? Array(gift.effects.prefix(1)) : gift.effects
        for (index, effect) in effects.enumerated() {
            try Task.checkCancellation()
            do {
                let player: any GiftEffectPlaying
                if case .native = effect, !reducedMotion {
                    guard let makeNativePlayer else { throw GiftMainEffectPlaybackError.unavailable }
                    player = makeNativePlayer()
                } else { player = makePlayer() }
                // 每一项退出前完成清理，下一项不会继承上一个播放器的画面或监听。
                defer { player.stop() }
                try await player.play(effect: effect, gift: gift, quantity: quantity)
                try Task.checkCancellation()
            // 取消需要结束整组任务；普通素材错误记录后仍允许播放后续配置。
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                logger.error("礼物第 \(index + 1) 项特效展示失败：\(error.localizedDescription, privacy: .public)")
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
}
