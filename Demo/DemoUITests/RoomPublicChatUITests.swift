import XCTest

final class RoomPublicChatUITests: XCTestCase {
    @MainActor
    func testFollowButtonTransitions() {
        let app = launchRoom()
        let follow = app.buttons["liveRoom.follow.button"]
        let chat = app.collectionViews["liveRoom.publicChat.scroll"]
        let originalWidth = follow.frame.width
        let chatFrame = chat.frame
        let latest = app.staticTexts["liveRoom.publicChat.latest"].label
        capture(app, "关注-渐变胶囊")
        for label in ["已关注", "关注直播间", "已关注"] {
            follow.tap()
            let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", label), object: follow)
            XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 5), .completed)
            XCTAssertEqual(follow.frame.width, originalWidth, accuracy: 0.5)
            XCTAssertEqual(chat.frame.minY, chatFrame.minY, accuracy: 0.5)
            XCTAssertEqual(chat.frame.height, chatFrame.height, accuracy: 0.5)
            XCTAssertEqual(app.staticTexts["liveRoom.publicChat.latest"].label, latest)
            capture(app, "关注状态-" + label)
        }
    }

    @MainActor
    func testPublicChatFollowSendAndGift() throws {
        let app = launchRoom()
        let follow = app.buttons["liveRoom.follow.button"]
        let chat = app.collectionViews["liveRoom.publicChat.scroll"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertTrue(chat.exists)
        XCTAssertLessThan(follow.frame.maxY, chat.frame.minY)
        follow.tap()
        let followed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "已关注"), object: follow)
        XCTAssertEqual(XCTWaiter.wait(for: [followed], timeout: 5), .completed)
        capture(app, "公屏-透明消息流与顶部关注")
        app.buttons["liveRoom.message.button"].tap()
        let input = app.textFields["liveRoom.message.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("Hello public chat")
        app.buttons["liveRoom.message.send"].tap()
        let latest = app.staticTexts["liveRoom.publicChat.latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.label.contains("Hello public chat"))
        capture(app, "公屏-发送后定位最新消息")
        app.buttons["liveRoom.gift.button"].tap()
        let recipient = app.buttons["liveRoom.gift.recipient.0"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 3))
        recipient.tap()
        app.buttons["liveRoom.gift.item.heart"].tap()
        app.buttons["liveRoom.gift.send"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.label.contains("送给"))
        capture(app, "公屏-成功送礼")
    }

    @MainActor
    func testPublicChatRTL() {
        let app = launchRoom(locale: "ar")
        let chat = app.collectionViews["liveRoom.publicChat.scroll"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["liveRoom.follow.button"].isHittable)
        XCTAssertTrue(app.staticTexts["liveRoom.publicChat.latest"].waitForExistence(timeout: 5))
        capture(app, "公屏-阿拉伯语")
    }

    @MainActor
    func testPublicChatAccessibilityTextSize() {
        let app = launchRoom(largeText: true)
        let follow = app.buttons["liveRoom.follow.button"]
        XCTAssertTrue(follow.waitForExistence(timeout: 5))
        XCTAssertTrue(follow.isHittable)
        XCTAssertTrue(app.staticTexts["liveRoom.publicChat.latest"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.collectionViews["liveRoom.publicChat.scroll"].frame.height, 100)
        capture(app, "公屏-辅助功能大字体")
    }

    @MainActor
    private func launchRoom(locale: String = "zh-Hans", largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", locale]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.liveRoom.title"]
        for _ in 0..<10 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        XCTAssertTrue(app.buttons["liveRoom.more.button"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
