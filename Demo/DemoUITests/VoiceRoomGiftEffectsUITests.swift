import XCTest

/// 从多特效栏目赠送原生、VAP、SVGA 组合，保留截图用于衔接与层级验收。
final class VoiceRoomGiftEffectsUITests: XCTestCase {
    /// 检查组合入口、播放期间点击穿透和结束清屏，记录远程动画衔接画面。
    @MainActor
    func testSendRemoteGiftEffectsFromSheet() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "zh-Hans"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.liveRoom.title"]
        for _ in 0..<10 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let giftButton = app.buttons["liveRoom.gift.button"]
        XCTAssertTrue(giftButton.waitForExistence(timeout: 10))
        giftButton.tap()
        let recipient = app.buttons["liveRoom.gift.recipient.0"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap()
        app.buttons["liveRoom.gift.category.multiple"].tap()
        let grid = app.collectionViews["liveRoom.gift.grid"]
        let vap = app.buttons["liveRoom.gift.item.flowerDuet"]
        for _ in 0..<4 where !vap.isHittable { grid.swipeUp() }
        XCTAssertTrue(vap.isHittable)
        capture(app, "多特效组合礼物")
        vap.tap()
        let send = app.buttons["liveRoom.gift.send"]
        XCTAssertTrue(send.isHittable)
        send.tap()
        XCTAssertTrue(app.buttons["liveRoom.gift.category.svga"].isHittable, "组合播放期间不能阻挡礼物面板")
        for second in [3, 8, 15, 23, 25, 27, 29, 32] {
            let previous = [3: 0, 8: 3, 15: 8, 23: 15, 25: 23, 27: 25, 29: 27, 32: 29][second]!
            try await Task.sleep(nanoseconds: UInt64(second - previous) * 1_000_000_000)
            capture(app, "组合赠送后第\(second)秒")
            XCTAssertTrue(send.isHittable)
        }
        // 再次赠送，在组合仍播放时切后台，验证取消后不恢复旧任务。
        send.tap()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        capture(app, "第二次组合播放中切后台前")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertTrue(send.isHittable)
        capture(app, "播放中取消并返回前台后的礼物面板")
    }

    /// 将系统截图附加到 xcresult，不使用无法捕获 Metal 内容的 layer.render。
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
