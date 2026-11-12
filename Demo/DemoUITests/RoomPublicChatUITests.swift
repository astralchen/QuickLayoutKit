import XCTest

final class RoomPublicChatUITests: XCTestCase {
    @MainActor
    func testStageStaysFixedWhileSwipingSeatsAndChat() {
        let app = launchRoom()
        let header = app.buttons["liveRoom.follow.button"]
        let stage = app.otherElements["liveRoom.seat.stage"]
        let lastSeat = app.buttons["liveRoom.seat.button.8"]
        let chat = app.collectionViews["liveRoom.publicChat.scroll"]
        XCTAssertTrue(lastSeat.waitForExistence(timeout: 5))
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        let headerFrame = header.frame
        let seatFrame = lastSeat.frame
        XCTAssertTrue(app.frame.contains(seatFrame))
        verifyArrangement(app, stage: stage, chat: chat)

        stage.swipeUp()
        XCTAssertEqual(header.frame, headerFrame)
        XCTAssertEqual(lastSeat.frame, seatFrame)

        chat.swipeDown()
        let firstMessage = app.staticTexts["liveRoom.publicChat.message.0"]
        XCTAssertTrue(firstMessage.isHittable)
        let firstY = firstMessage.frame.minY
        let latest = app.staticTexts["liveRoom.publicChat.latest"]
        let overflows = !latest.isHittable || latest.frame.maxY > chat.frame.maxY
        chat.swipeUp()
        if overflows {
            XCTAssertTrue(!firstMessage.isHittable || firstMessage.frame.minY < firstY)
        }
        XCTAssertTrue(latest.isHittable)
        XCTAssertEqual(header.frame, headerFrame)
        XCTAssertEqual(lastSeat.frame, seatFrame)
        capture(app, "固定麦位与公屏")
    }

    @MainActor
    func testRoomReflowsWhenRotated() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchRoom()
        let chat = app.collectionViews["liveRoom.publicChat.scroll"]
        let stage = app.otherElements["liveRoom.seat.stage"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return orientation == .portrait ? frame.height > frame.width && chat.exists && chat.isHittable
                    : frame.width > frame.height
            }, object: nil)
            let result = XCTWaiter.wait(for: [ready], timeout: 5)
            capture(app, "语音房旋转-\(orientation.rawValue)")
            XCTAssertEqual(result, .completed, app.debugDescription)
            // iPhone 双紧凑环境按标准 split 规则收起辅助公屏；返回竖屏必须恢复同一内容。
            // 公屏仍可见的宽屏环境继续检查滚动和列对齐，不能用此分支跳过竖屏恢复。
            if orientation != .portrait && !chat.isHittable {
                XCTAssertTrue(stage.isHittable)
                continue
            }
            XCTAssertTrue(chat.isHittable)
            verifyArrangement(app, stage: stage, chat: chat)
            XCTAssertTrue(app.buttons["liveRoom.gift.button"].isHittable)
            chat.swipeDown()
            chat.swipeUp()
            verifyArrangement(app, stage: stage, chat: chat)
            if orientation == .landscapeLeft { capture(app, "语音房横屏排列") }
        }
    }

    @MainActor
    private func verifyArrangement(_ app: XCUIApplication, stage: XCUIElement, chat: XCUIElement) {
        let header = app.buttons["liveRoom.room.avatar.button"]
        let bar = app.otherElements["liveRoom.actionBar"]
        // 排列组件根据当前环境选轴；竖向窗口也可能受 Duo 的姿态影响。
        XCTAssertTrue(stage.frame.maxY <= chat.frame.minY + 1 || stage.frame.maxX <= chat.frame.minX + 1)
        XCTAssertTrue(header.isHittable)
        XCTAssertEqual(bar.frame.minX, chat.frame.minX, accuracy: 1)
        XCTAssertEqual(bar.frame.width, chat.frame.width, accuracy: 1)
    }

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
        verifyArrangement(app, stage: app.otherElements["liveRoom.seat.stage"], chat: chat)
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
    func testPublicChatLanguageRoundTrip() {
        let app = launchRoom()
        let latest = app.staticTexts["liveRoom.publicChat.latest"]
        let roundTrip = [("العربية", "الأغنية التالية"), ("简体中文", "下一首送给大家")]
        for (step, target) in (roundTrip + roundTrip).enumerated() {
            let (language, message) = target
            app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let localized = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", message), object: latest
            )
            XCTAssertEqual(XCTWaiter.wait(for: [localized], timeout: 5), .completed)
            let stage = app.otherElements["liveRoom.seat.stage"].frame
            let chat = app.collectionViews["liveRoom.publicChat.scroll"].frame
            if stage.maxY > chat.minY + 1 {
                if language == "العربية" {
                    XCTAssertLessThanOrEqual(chat.maxX, stage.minX + 1)
                } else {
                    XCTAssertLessThanOrEqual(stage.maxX, chat.minX + 1)
                }
            }
            capture(app, "公屏切换-\(step + 1)-" + language)
        }
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
        let route = app.buttons.matching(identifier: "app.tab.voiceRoom").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertTrue(route.isHittable)
        route.tap()
        XCTAssertTrue(app.buttons["liveRoom.more.button"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
