import OSLog
import SVGAView
import UIKit
import VAPView
import XCTest
@testable import Demo

private let logger = Logger(subsystem: "Demo.Tests", category: "GiftEffectPrefetchIntegrationTests")

/// 真实 SDK/网络验收，与不访问网络的调度测试分开运行。
@MainActor
final class GiftEffectPrefetchIntegrationTests: XCTestCase {
    func testColdPrefetchAndCachedNativeVAPSVGACombinationTwice() async throws {
        let original = try XCTUnwrap(Gift.catalog.first { $0.id == "flowerDuet" })
        let token = UUID().uuidString
        // 唯一 URL 获得独立缓存键，不清空既有播放器缓存。
        func isolatedURL(_ url: URL) throws -> URL {
            var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "gift_prefetch_test", value: token)]
            return try XCTUnwrap(components.url)
        }
        var gift = original
        gift.effects = try original.effects.map { effect in
            switch effect {
            case .native: effect
            case .vap(let url): .vap(try isolatedURL(url))
            case .svga(let url): .svga(try isolatedURL(url))
            }
        }
        for effect in gift.effects {
            switch effect {
            case .native: break
            case .vap(let url):
                let status = await VAPView.cacheStatus(source: url.absoluteString)
                guard case .missing = status else { XCTFail("VAP 测试 URL 必须是冷缓存"); return }
            case .svga(let url):
                let status = await SVGAView.cacheStatus(remoteURL: url)
                XCTAssertEqual(status, .missing)
            }
        }

        var prepared: [GiftEffect] = []
        var failures: [String] = []
        let prefetcher = GiftEffectPrefetcher { effect in
            do {
                try await GiftEffectPrefetcher.loadResource(effect)
                prepared.append(effect)
            } catch {
                failures.append(error.localizedDescription)
                throw error
            }
        }
        let request = prefetcher.register(effects: gift.effects)
        defer { prefetcher.cancelAll() }
        try await waitForTaskCondition(timeout: 60) { prepared.count + failures.count == 2 }
        XCTAssertTrue(failures.isEmpty, "真实预下载失败：\(failures)")
        guard failures.isEmpty else { return }
        for effect in gift.effects {
            switch effect {
            case .native: break
            case .vap(let url):
                guard case .cached = await VAPView.cacheStatus(source: url.absoluteString) else {
                    XCTFail("VAP 预下载后应存在磁盘缓存"); return
                }
            case .svga(let url):
                guard case .cached = await SVGAView.cacheStatus(remoteURL: url) else {
                    XCTFail("SVGA 预加载后应存在可复用缓存"); return
                }
            }
        }
        logger.notice("GIFT_PREFETCH_COLD_PASS formats=VAP,SVGA")
        prefetcher.release(request)

        let controller = VoiceRoomViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        var started: [GiftEffect] = []
        var completed: [GiftEffect] = []
        controller.giftMainEffectCoordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }) { [weak controller] in
            let container = controller?.giftEffectOverlayView ?? UIView()
            return ObservedGiftSDKPlayer(container: container) { [weak controller] effect, didFinish, error in
                if let error { failures.append(error.localizedDescription) }
                else if didFinish { completed.append(effect) }
                else {
                    XCTAssertEqual(controller?.activeGiftFlightCount, 0, "远程效果必须在原生飞行结束后开始")
                    started.append(effect)
                }
            }
        }
        defer {
            controller.giftMainEffectCoordinator.deactivate()
            window.isHidden = true
        }
        let recipient = try XCTUnwrap(controller.viewModel.state.visibleRecipients.first)
        let remoteEffects = gift.effects.filter { if case .native = $0 { false } else { true } }
        controller.giftMainEffectCoordinator.activate()
        for iteration in 1...2 {
            controller.deliver(gift: gift, to: [recipient], quantity: 1)
            try await waitForTaskCondition { controller.activeGiftFlightCount > 0 }
            try await waitForTaskCondition(timeout: 65) { !controller.giftMainEffectCoordinator.isPlaying }
            XCTAssertTrue(failures.isEmpty, "真实播放失败：\(failures)")
            XCTAssertEqual(started, Array(repeating: remoteEffects, count: iteration).flatMap { $0 })
            XCTAssertEqual(completed, started)
            XCTAssertTrue(controller.giftEffectOverlayView.subviews.isEmpty)
            logger.notice("GIFT_PREFETCH_COMBINATION_PASS iteration=\(iteration, privacy: .public) order=native,VAP,SVGA")
        }
    }
}

/// 仅记录真实 SDK 适配器的开始和完成，不替代下载、解码或播放。
@MainActor
private final class ObservedGiftSDKPlayer: GiftEffectPlaying {
    private let player: GiftMainEffectPlayer
    private let observe: (GiftEffect, Bool, Error?) -> Void

    init(container: UIView, observe: @escaping (GiftEffect, Bool, Error?) -> Void) {
        player = GiftMainEffectPlayer(containerView: container, reduceMotionEnabled: { false })
        self.observe = observe
    }

    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws {
        observe(effect, false, nil)
        do {
            try await player.play(effect: effect, gift: gift, quantity: quantity)
            observe(effect, true, nil)
        } catch {
            observe(effect, false, error)
            throw error
        }
    }

    func stop() { player.stop() }
}
