import Foundation
import OSLog

/// 一份礼物的异步播放任务；配置顺序直接由逐项 await 表达，不另建内部队列。
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

    /// 严格按列表顺序播放；普通错误继续，取消立即退出，整组结束后报告首个展示错误。
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
                defer { player.stop() }
                try await player.play(effect: effect, gift: gift, quantity: quantity)
                try Task.checkCancellation()
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
