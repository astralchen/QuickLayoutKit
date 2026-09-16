import Foundation

/// 原生飞行与到达动画的异步适配器，底层回调只保留在渲染边界。
@MainActor
final class GiftNativeEffectPlayer: GiftEffectPlaying {
    /// 房间在实际开始时解析坐标，并返回本次原生动画的清理行为。
    typealias Start = @MainActor (GiftEffectStyle, Gift, Int, @escaping GiftPlaybackOperation.Completion) -> GiftPlaybackOperation.Cleanup
    /// 将原生动画回调转换为取消安全的异步结果。
    private let playback = GiftPlaybackOperation()
    /// 由房间提供的原生渲染入口，不持有队列。
    private let start: Start

    /// 保存实际渲染入口，不提前查询坐标或创建动画。
    init(start: @escaping Start) { self.start = start }

    /// 等待本次所有收礼人的原生到达动画；不复制或修改礼物配置列表。
    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws {
        guard case .native(let style) = effect else { throw GiftMainEffectPlaybackError.unavailable }
        try await playback.run { [start] completion in start(style, gift, quantity, completion) }
    }

    /// 同步取消本次原生动画并结束异步等待。
    func stop() { playback.stop() }
}
