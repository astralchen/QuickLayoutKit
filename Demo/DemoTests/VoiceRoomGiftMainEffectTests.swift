import Foundation
import AppLocalization
import Testing
import UIKit
@testable import Demo

/// 不依赖网络的主特效配置、队列和生命周期回归。
@MainActor
@Suite(.serialized)
struct VoiceRoomGiftMainEffectTests {
    /// 使用真实目录确保两种资源已加入应用 Bundle。
    private func gift(_ id: String = "flowerJourney") throws -> Gift {
        try #require(Gift.catalog.first { $0.id == id })
    }

    @Test func bundledConfigurationAndCatalog() async throws {
        #expect(Gift.catalog.count == 269)
        #expect(Set(Gift.catalog.map(\.id)).count == 269)
        let vap = try gift()
        let svga = try gift("flowerBouquet")
        #expect(vap.price == 520 && svga.price == 520)
        #expect(GiftCategory.romantic.includes(vap))
        #expect(GiftCategory.romantic.includes(svga))
        let vapEntries = try GiftEffectResources.entries(named: "gift_effects_mp4")
        let svgaEntries = try GiftEffectResources.entries(named: "gift_effects_svga")
        let vapGifts = Gift.catalog.filter { GiftCategory.vap.includes($0) && $0.effects.count == 1 }
        let svgaGifts = Gift.catalog.filter { GiftCategory.svga.includes($0) && $0.effects.count == 1 }
        #expect(vapEntries.count == 145 && vapGifts.count == 145)
        #expect(svgaEntries.count == 105 && svgaGifts.count == 105)
        #expect(Gift.catalog.filter { $0.effects == [.native($0.effectStyle)] }.count == 18)
        #expect(vapGifts.map(\.sourceName) == vapEntries.map { Optional($0.name) })
        #expect(svgaGifts.map(\.sourceName) == svgaEntries.map { Optional($0.name) })
        for (gifts, entries, ext) in [(vapGifts, vapEntries, "mp4"), (svgaGifts, svgaEntries, "svga")] {
            for (gift, entry) in zip(gifts, entries) {
                let url = try #require(entry.remoteURL(pathExtension: ext))
                #expect(gift.effects == [ext == "mp4" ? .vap(url) : .svga(url)])
                #expect(gift.price == 520)
            }
        }
        // 上游共用素材的不同名称必须各自保留，不能按 URL 合并礼物。
        #expect(Set(vapEntries.map(\.url)).count < vapGifts.count)
        #expect(Set(svgaEntries.map(\.url)).count < svgaGifts.count)
        defer { Localization.setLocale(identifier: "en-US") }
        for language in ["zh-Hans", "en", "ar"] {
            Localization.setLocale(identifier: language)
            for gift in vapGifts.dropFirst() + svgaGifts.dropFirst() {
                #expect(gift.localizedTitle == gift.sourceName)
            }
        }
        #expect(vap.effects.first == .vap(try #require(vapEntries.first { $0.name == "花下与君游" }?.remoteURL(pathExtension: "mp4"))))
        #expect(svga.effects.first == .svga(try #require(svgaEntries.first { $0.name == "萌萌花束" }?.remoteURL(pathExtension: "svga"))))
        #expect(vap.totalCost(quantity: 10, recipientCount: 2).cost == 10_400)
        #expect(vap.totalCost(quantity: Int.max, recipientCount: 2).overflow)
    }

    /// 同一礼物可任意排列；失败继续、重复配置保留，下一赠送不能插入。
    @Test func combinationFollowsConfiguredOrderAndKeepsGiftAtomic() async throws {
        let vap = try #require(gift().effects.first)
        let svga = try #require(gift("flowerBouquet").effects.first)
        let native = GiftEffect.native(.burst)
        for effects in [[native, vap, svga], [native, svga, vap], [vap, native, svga], [svga, vap, native], [vap, vap]] {
            var players: [FakeGiftEffectPlayer] = []
            let factory: @MainActor () -> any GiftEffectPlaying = {
                let player = FakeGiftEffectPlayer()
                players.append(player)
                return player
            }
            let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }, makePlayer: factory)
            coordinator.activate()
            var combination = try gift("flowerDuet")
            combination.effects = effects
            coordinator.enqueue(gift: combination, quantity: 10, makeNativePlayer: factory)
            coordinator.enqueue(gift: try gift(), quantity: 1)
            for index in effects.indices {
                try await waitForTaskCondition { players.count == index + 1 }
                #expect(players.compactMap(\.effect) == Array(effects.prefix(index + 1)))
                #expect(players[index].receivedGift == combination, "播放器收到完整礼物，不通过改写 effects 表达当前项")
                #expect(players[index].quantity == 10 && coordinator.pendingCount == 1)
                players[index].complete(index == 0 ? .failure(URLError(.badServerResponse)) : .success(()))
            }
            try await waitForTaskCondition { players.count == effects.count + 1 }
            #expect(players.compactMap(\.effect) == effects + [vap])
            #expect(players.dropLast().allSatisfy { $0.stopCount == 1 })
            players.last?.complete(.success(()))
            try await waitForTaskCondition { !coordinator.isPlaying }
        }
    }

    /// 取消组合等待当前原生退出，之后不会创建远程播放器；重启只处理新请求。
    @Test func combinationCancellationAndRestart() async throws {
        var remotePlayers: [FakeGiftEffectPlayer] = []
        let native = FakeGiftEffectPlayer()
        let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }) {
            let player = FakeGiftEffectPlayer()
            remotePlayers.append(player)
            return player
        }
        coordinator.activate()
        let old = try #require(coordinator.enqueue(gift: try gift("flowerDuet"), quantity: 30, makeNativePlayer: { native }))
        await native.started.wait()
        coordinator.deactivate()
        _ = await old.result
        #expect(native.stopCount == 1 && remotePlayers.isEmpty)
        coordinator.activate()
        coordinator.enqueue(gift: try gift(), quantity: 1)
        try await waitForTaskCondition { remotePlayers.count == 1 }
        native.complete(.success(()))
        #expect(coordinator.isPlaying)
        coordinator.deactivate()
        try await waitForTaskCondition { !coordinator.isPlaying }
        #expect(remotePlayers[0].stopCount == 1)
    }

    /// 减少动态效果只创建一次静态展示，不创建任何原生组合播放器。
    @Test func combinationReducedMotionRunsOnce() async throws {
        var players: [FakeGiftEffectPlayer] = []
        let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { true }) {
            let player = FakeGiftEffectPlayer()
            players.append(player)
            return player
        }
        coordinator.activate()
        coordinator.enqueue(gift: try gift("flowerDuet"), quantity: 30, makeNativePlayer: {
            Issue.record("减少动态效果不得创建原生飞行播放器")
            return FakeGiftEffectPlayer()
        })
        try await waitForTaskCondition { players.count == 1 }
        #expect(players[0].quantity == 30)
        players[0].complete(.success(()))
        try await waitForTaskCondition { !coordinator.isPlaying }
        #expect(players.count == 1)
    }

    /// 组合一次扣款与消息，等全部原生到达后才启动两个远程效果。
    @Test func combinationBusinessRunsNativeThenRemoteOnce() async throws {
        let controller = VoiceRoomViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        var players: [FakeGiftEffectPlayer] = []
        controller.giftMainEffectCoordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }) {
            let player = FakeGiftEffectPlayer()
            players.append(player)
            return player
        }
        controller.giftMainEffectCoordinator.activate()
        let combination = try gift("flowerDuet")
        let recipients = Array(controller.viewModel.state.visibleRecipients.prefix(2))
        let request = GiftSendRequest(gift: combination, recipients: recipients, quantity: 1, totalCost: 1_040)
        #expect(controller.processGiftSendRequest(request) == 11_760)
        try await waitForTaskCondition { controller.activeGiftFlightCount == 2 }
        #expect(controller.giftDeliveryCount == 1 && players.isEmpty)
        try await waitForTaskCondition { players.count == 1 }
        #expect(controller.activeGiftFlightCount == 0)
        players[0].complete(.success(()))
        try await waitForTaskCondition { players.count == 2 }
        players[1].complete(.success(()))
        try await waitForTaskCondition { !controller.giftMainEffectCoordinator.isPlaying }
        #expect(controller.giftBalance == 11_760 && controller.giftDeliveryCount == 1)
    }

    /// 资源格式与条目错误只产生诊断，不生成可以赠送的无效配置。
    @Test func invalidConfigurationIsRejected() {
        for value in ["", "file:///tmp/gift.mp4", "https:///gift.mp4", "https://example.com/gift.svga"] {
            #expect(GiftEffectResourceEntry(name: "gift", url: value).remoteURL(pathExtension: "mp4") == nil)
        }
        #expect(GiftEffectResources.remoteURL(list: "missing-gift-config", name: "missing", pathExtension: "mp4") == nil)
        #expect(GiftEffectResources.remoteURL(list: "gift_effects_mp4", name: "missing", pathExtension: "mp4") == nil)
    }

    /// SDK 同步失败由异步接口抛出，失败赠送之后仍可处理下一份。
    @Test func synchronousFailuresAdvanceQueue() async throws {
        var players: [FakeGiftEffectPlayer] = []
        let coordinator = GiftMainEffectCoordinator {
            let player = FakeGiftEffectPlayer()
            player.failsSynchronously = players.isEmpty
            players.append(player)
            return player
        }
        coordinator.activate()
        coordinator.enqueue(gift: try gift(), quantity: 1)
        coordinator.enqueue(gift: try gift("flowerBouquet"), quantity: 1)
        try await waitForTaskCondition { players.count == 2 }
        #expect(players[0].stopCount == 1)
        players[1].complete(.success(()))
        try await waitForTaskCondition { !coordinator.isPlaying }
    }

    /// 整组超时请求取消，当前效果实际退出后才继续下一份赠送。
    @Test func timeoutStopsGroupAndStartsNext() async throws {
        var players: [FakeGiftEffectPlayer] = []
        let coordinator = GiftMainEffectCoordinator(timeout: 0.1) {
            let player = FakeGiftEffectPlayer()
            players.append(player)
            return player
        }
        coordinator.activate()
        var combination = try gift("flowerDuet")
        combination.effects = Array(combination.effects.dropFirst())
        coordinator.enqueue(gift: combination, quantity: 1)
        coordinator.enqueue(gift: try gift(), quantity: 1)
        try await waitForTaskCondition { players.count == 2 }
        #expect(players[0].stopCount == 1)
        #expect(players[1].receivedGift?.id == "flowerJourney")
        coordinator.deactivate()
        try await waitForTaskCondition { !coordinator.isPlaying }
        #expect(players[1].stopCount == 1)
    }

    /// 远程礼物不会创建飞行，多人数量只影响一次业务费用而不重复播放。
    @Test func remoteGiftsUseOneQueueItemForMultipleRecipientsAndPreserveBalance() async throws {
        let controller = VoiceRoomViewController()
        controller.loadViewIfNeeded()
        let player = FakeGiftEffectPlayer()
        controller.giftMainEffectCoordinator = GiftMainEffectCoordinator { player }
        controller.giftMainEffectCoordinator.activate()
        let request = GiftSendRequest(gift: try gift(), recipients: Array(controller.viewModel.state.visibleRecipients.prefix(2)), quantity: 10, totalCost: 10_400)
        #expect(controller.processGiftSendRequest(request) == 2_400)
        await player.started.wait()
        #expect(player.quantity == 10 && controller.activeGiftFlightCount == 0)
        #expect(controller.lastGiftAnimationOrigin == nil)
        player.complete(.failure(URLError(.badServerResponse)))
        try await waitForTaskCondition { !controller.giftMainEffectCoordinator.isPlaying }
        #expect(controller.giftBalance == 2_400 && controller.processGiftSendRequest(request) == nil)
    }

    /// 实际静态展示可以随容器变化，并通过 async 返回，不创建远程 SDK 视图。
    @Test func reducedMotionAvoidsRemotePlayersAndResizesWithContainer() async throws {
        let controller = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        controller.view.addSubview(container)
        let player = GiftMainEffectPlayer(containerView: container, reduceMotionEnabled: { true })
        let gift = try gift("flowerDuet")
        let task = Task { try await player.play(effect: .native(.burst), gift: gift, quantity: 30) }
        try await waitForTaskCondition { !container.subviews.isEmpty }
        let overlay = try #require(container.subviews.first)
        #expect(overlay.accessibilityIdentifier == "liveRoom.gift.effect.reducedMotion")
        #expect(!overlay.isUserInteractionEnabled)
        container.frame.size = CGSize(width: 768, height: 1024)
        container.layoutIfNeeded()
        #expect(overlay.frame == container.bounds)
        try await task.value
        #expect(container.subviews.isEmpty)
    }

    /// 只响应所属 Scene；实际导航离开清空任务，返回不恢复旧请求。
    @Test func sceneBackgroundAndPageDisappearanceClearPlayback() async throws {
        let notifications = NotificationCenter()
        let controller = VoiceRoomViewController(viewModel: VoiceRoomViewModel(), notificationCenter: notifications)
        let navigation = UINavigationController(rootViewController: controller)
        var players: [FakeGiftEffectPlayer] = []
        controller.giftMainEffectCoordinator = GiftMainEffectCoordinator {
            let player = FakeGiftEffectPlayer()
            players.append(player)
            return player
        }
        let window = try makeVisibleTestWindow(rootViewController: navigation)
        defer { window.isHidden = true }
        try await waitForTaskCondition { controller.giftMainEffectCoordinator.isActive }
        let scene = try #require(window.windowScene)
        controller.giftMainEffectCoordinator.enqueue(gift: try gift(), quantity: 1)
        controller.giftMainEffectCoordinator.enqueue(gift: try gift("flowerBouquet"), quantity: 1)
        try await waitForTaskCondition { players.count == 1 }
        notifications.post(name: UIScene.didEnterBackgroundNotification, object: NSObject())
        #expect(controller.giftMainEffectCoordinator.isPlaying)
        notifications.post(name: UIScene.didEnterBackgroundNotification, object: scene)
        try await waitForTaskCondition { !controller.giftMainEffectCoordinator.isPlaying }
        #expect(players[0].stopCount == 1 && controller.giftMainEffectCoordinator.pendingCount == 0)
        notifications.post(name: UIScene.didActivateNotification, object: scene)
        #expect(controller.giftMainEffectCoordinator.isActive && !controller.giftMainEffectCoordinator.isPlaying)
        controller.giftMainEffectCoordinator.enqueue(gift: try gift(), quantity: 1)
        try await waitForTaskCondition { players.count == 2 }
        navigation.pushViewController(UIViewController(), animated: false)
        try await waitForTaskCondition { !controller.giftMainEffectCoordinator.isActive && !controller.giftMainEffectCoordinator.isPlaying }
        notifications.post(name: UIScene.didActivateNotification, object: scene)
        #expect(!controller.giftMainEffectCoordinator.isActive && players[1].stopCount == 1)
    }

    /// 意外释放拥有者会请求取消，并由适配器结束正在等待的播放。
    @Test func releasingCoordinatorStopsCurrentPlayback() async throws {
        let player = FakeGiftEffectPlayer()
        var coordinator: GiftMainEffectCoordinator? = GiftMainEffectCoordinator { player }
        coordinator?.activate()
        let task = try #require(coordinator?.enqueue(gift: try gift(), quantity: 1))
        await player.started.wait()
        coordinator = nil
        _ = await task.result
        #expect(player.stopCount == 1)
    }
}

/// 可控异步播放器，测试只等待明确的开始事件，不依赖实际 SDK 或固定 yield。
@MainActor
private final class FakeGiftEffectPlayer: GiftEffectPlaying {
    /// 明确的异步启动事件。
    let started = TaskTestSignal()
    /// 收到的当前效果，不从 gift.effects 推测。
    private(set) var effect: GiftEffect?
    /// 收到的完整礼物数据。
    private(set) var receivedGift: Gift?
    /// 收到的赠送数量。
    private(set) var quantity = 0
    /// 验证拥有者清理次数。
    private(set) var stopCount = 0
    /// 模拟 SDK 在启动阶段立即失败。
    var failsSynchronously = false
    /// 本次可控异步等待。
    private var continuation: CheckedContinuation<Void, Error>?
    /// 挂起直到测试指定结果或拥有者停止。
    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws {
        self.effect = effect
        receivedGift = gift
        self.quantity = quantity
        if failsSynchronously { started.signal(); throw URLError(.cannotDecodeContentData) }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.signal()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.complete(.failure(CancellationError())) }
        }
    }
    /// 同步终止等待，不允许取消后的测试结果再次恢复。
    func stop() { stopCount += 1; complete(.failure(CancellationError())) }
    /// 仅第一次测试结果生效，SDK 重复回调由适配器专用测试覆盖。
    func complete(_ result: Result<Void, Error>) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
