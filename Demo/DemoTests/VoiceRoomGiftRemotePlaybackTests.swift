import UIKit
import XCTest
import SVGAView
import VAPView
@testable import Demo

/// 真实网络集成验证；通过独立类筛选运行，不与无网络队列测试混淆。
@MainActor
final class VoiceRoomGiftRemotePlaybackTests: XCTestCase {
    /// 从远程地址连续播放两种格式两轮，覆盖首次加载和库缓存复用路径。
    func testRemoteVAPAndSVGAPlaybackTwice() async throws {
        let controller = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        for iteration in 1...2 {
            for id in ["flowerJourney", "flowerBouquet"] {
                let gift = try XCTUnwrap(Gift.catalog.first { $0.id == id })
                let result = await play(gift, in: controller.view)
                switch result {
                case .success:
                    print("GIFT_REMOTE_PASS gift=\(id) iteration=\(iteration)")
                case .failure(let error):
                    XCTFail("\(id) 第 \(iteration) 次远程播放失败：\(error)")
                }
                switch gift.effects.first {
                case .vap(let url):
                    if case .cached = await VAPView.cacheStatus(source: url.absoluteString) {
                        print("GIFT_CACHE_PASS format=VAP iteration=\(iteration)")
                    } else { XCTFail("VAP 完成播放后应存在库管理的缓存") }
                case .svga(let url):
                    if case .cached = await SVGAView.cacheStatus(remoteURL: url) {
                        print("GIFT_CACHE_PASS format=SVGA iteration=\(iteration)")
                    } else { XCTFail("SVGA 完成播放后应存在库管理的缓存") }
                case .native, nil:
                    XCTFail("远程测试礼物缺少主特效配置")
                }
                XCTAssertTrue(controller.view.subviews.isEmpty, "完成后必须清空特效视图")
            }
        }
    }

    /// 真实 HTTP 404 与错误文件内容均必须产生失败终态，并清空画面。
    func testRemoteMissingAndInvalidResourcesFinishWithFailure() async throws {
        let controller = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        for format in ["vap", "svga"] {
            for source in [
                "https://raw.githubusercontent.com/astralchen/VAPView/1.0.0/does-not-exist.mp4",
                "https://raw.githubusercontent.com/astralchen/VAPView/1.0.0/README.md",
            ] {
                var gift = try XCTUnwrap(Gift.catalog.first { $0.id == "flowerJourney" })
                let url = try XCTUnwrap(URL(string: source))
                gift.effects = [format == "vap" ? .vap(url) : .svga(url)]
                let result = await play(gift, in: controller.view)
                if case .success = result { XCTFail("无效远程素材不能报告播放成功") }
                XCTAssertTrue(controller.view.subviews.isEmpty)
            }
        }
    }

    /// 远程加载实际开始后取消，异步调用必须结束且画面保持清空。
    func testCancelRemoteLoadSuppressesCompletion() async throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        for id in ["flowerJourney", "flowerBouquet"] {
            let gift = try XCTUnwrap(Gift.catalog.first { $0.id == id })
            let effect = try XCTUnwrap(gift.effects.first)
            let player = GiftMainEffectPlayer(containerView: container, reduceMotionEnabled: { false })
            let task = Task { try await player.play(effect: effect, gift: gift, quantity: 1) }
            try await waitForTaskCondition { !container.subviews.isEmpty }
            task.cancel()
            if case .failure(let error) = await task.result { XCTAssertTrue(error is CancellationError) }
            else { XCTFail("取消播放必须以取消结果结束") }
            XCTAssertTrue(container.subviews.isEmpty)
        }
    }

    /// 直接等待原生句柄的结果，使用与正式播放相同的协作式超时。
    private func play(_ gift: Gift, in container: UIView) async -> Result<Void, Error> {
        let player = GiftMainEffectPlayer(containerView: container, reduceMotionEnabled: { false })
        let queue = SerialTaskQueue()
        let task = queue.addTask {
            try await withTimeout(60) {
                guard let effect = gift.effects.first else { throw GiftMainEffectPlaybackError.unavailable }
                try await player.play(effect: effect, gift: gift, quantity: 1)
            }
        }
        let result = await task.result
        withExtendedLifetime(queue) {}
        return result
    }
}
