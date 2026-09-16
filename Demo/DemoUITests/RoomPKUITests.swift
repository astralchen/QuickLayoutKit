import XCTest

final class RoomPKUITests: XCTestCase {
    @MainActor
    func testMenuCardsLocalGiftsAndExit() throws {
        let app = launchRoomPK()
        let more = app.buttons["liveRoom.more.button"]
        let current = app.buttons["liveRoom.seat.button.current.1"]
        let opponent = app.buttons["liveRoom.seat.button.opponent.1"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "liveRoom.seat.button.")).count, 18)
        capture(app, "厅PK-双房18麦")
        for (button, room) in [(current, "本房"), (opponent, "对方")] {
            button.tap()
            let seatLabel = app.staticTexts["liveRoom.userCard.seat"]
            XCTAssertTrue(seatLabel.waitForExistence(timeout: 3))
            XCTAssertEqual(seatLabel.label, "\(room) · 1 号麦")
            capture(app, "厅PK-\(room)资料卡")
            app.buttons["liveRoom.userCard.close"].tap()
        }
        app.buttons["liveRoom.gift.button"].tap()
        let recipient = app.buttons["liveRoom.gift.recipient.0"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "liveRoom.gift.recipient.")).count, 7)
        recipient.tap()
        app.buttons["liveRoom.gift.item.heart"].tap()
        let send = app.buttons["liveRoom.gift.send"]
        XCTAssertTrue(send.isEnabled)
        capture(app, "厅PK-仅本房收礼列表")
        send.tap()
        capture(app, "厅PK-本房送礼")
        // 点击面板之外的舞台关闭面板，继续验证菜单退出。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(more.isHittable)
        more.tap()
        app.buttons["结束 PK"].tap()
        XCTAssertTrue(app.buttons["liveRoom.seat.button.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(opponent.exists)
        capture(app, "厅PK-恢复九麦")
    }

    @MainActor
    func testPKKeyboardKeepsSeatsAndInputVisible() throws {
        let app = launchRoomPK()
        app.buttons["liveRoom.message.button"].tap()
        let input = app.textFields["liveRoom.message.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText("PK")
        for side in ["current", "opponent"] {
            let lastSeat = app.buttons["liveRoom.seat.button.\(side).8"]
            XCTAssertTrue(lastSeat.exists)
            XCTAssertLessThanOrEqual(lastSeat.frame.maxY, input.frame.minY,
                "输入条不能遮住 \(side) 最后一排麦位")
        }
        capture(app, "厅PK-键盘展开")
        app.buttons["liveRoom.message.cancel"].tap()
        XCTAssertTrue(app.buttons["liveRoom.seat.button.opponent.0"].exists)
        capture(app, "厅PK-收起键盘")
    }

    @MainActor
    private func launchRoomPK() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "zh-Hans"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.liveRoom.title"]
        for _ in 0..<10 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let more = app.buttons["liveRoom.more.button"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        app.buttons["厅 PK"].tap()
        XCTAssertTrue(app.buttons["liveRoom.seat.button.current.1"].waitForExistence(timeout: 5))
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
