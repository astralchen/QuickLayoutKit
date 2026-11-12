import XCTest

final class SafeAreaInsetUITests: XCTestCase {
    @MainActor func testScenariosAndReachableLastRowLTR() throws {
        try verifyScenarios(locale: "zh-Hans", titles: ["底部", "顶部", "前缘", "后缘", "底部连续插入 A + B", "顶部 + 底部", "底部输入栏与键盘", "不插入内容"])
    }
    @MainActor func testScenariosAndReachableLastRowRTL() throws {
        try verifyScenarios(locale: "ar", titles: ["أسفل", "أعلى", "البداية", "النهاية", "إدراجان في الأسفل A + B", "أعلى وأسفل", "إدخال سفلي ولوحة مفاتيح", "بدون إدراج"])
    }

    @MainActor func testExpandInsetWhileAlreadyAtBottom() throws {
        let app = openPage(locale: "zh-Hans")
        let scroll = app.scrollViews["safeAreaInset.scroll"]
        let bar = app.otherElements["safeAreaInset.primary"]
        let last = app.staticTexts["safeAreaInset.row.24"]
        // 多次真实滑动到物理尾部，随后只点尺寸按钮，不补滚动操作。
        for _ in 0..<8 { scroll.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, bar.frame.minY - 7)
        let initialLastY = last.frame.maxY
        let initialHeight = bar.frame.height
        app.buttons["safeAreaInset.size"].tap()
        XCTAssertGreaterThan(bar.frame.height, initialHeight)
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, bar.frame.minY - 7)
        XCTAssertEqual(initialLastY - last.frame.maxY, bar.frame.height - initialHeight, accuracy: 1)
        capture(app, "SafeAreaInset-expanded-at-bottom")
        app.buttons["safeAreaInset.size"].tap()
        XCTAssertEqual(last.frame.maxY, initialLastY, accuracy: 1)
        XCTAssertLessThanOrEqual(last.frame.maxY, bar.frame.minY - 7)
    }

    @MainActor func testKeyboardAndDynamicHeight() throws {
        // 不依赖上一项用例的设备方向；横屏失败退出可能不会执行测试方法里的 defer。
        XCUIDevice.shared.orientation = .portrait
        let app = openPage(locale: "en")
        let scroll = app.scrollViews["safeAreaInset.scroll"]
        let bar = app.otherElements["safeAreaInset.primary"]
        let initialHeight = bar.frame.height
        app.buttons["safeAreaInset.size"].tap()
        XCTAssertGreaterThan(bar.frame.height, initialHeight)
        app.buttons["safeAreaInset.size"].tap()
        select("Bottom input and keyboard", in: app)
        let field = app.textFields["safeAreaInset.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let initialY = field.frame.maxY
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let movedAboveKeyboard = NSPredicate { _, _ in field.frame.maxY < initialY - 1 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: movedAboveKeyboard, object: nil)], timeout: 5), .completed,
                       "field=\(field.frame), keyboard=\(app.keyboards.firstMatch.frame)")
        // 点击屏幕键盘按键，避免模拟器的合成硬件输入使软件键盘退到屏幕外。
        for letter in ["i", "n", "s", "e", "t"] {
            app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch.tap()
        }
        XCTAssertLessThan(field.frame.maxY, initialY, "keyboard=\(app.keyboards.firstMatch.frame)")
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(field.frame.minX, bar.frame.minX + 15)
        XCTAssertLessThanOrEqual(field.frame.maxX, bar.frame.maxX - 15)
        XCTAssertGreaterThanOrEqual(field.frame.minY, bar.frame.minY)
        XCTAssertLessThanOrEqual(field.frame.maxY, bar.frame.maxY)
        let title = app.staticTexts["safeAreaInset.barTitle"].firstMatch
        let stage = app.otherElements["safeAreaInset.stage"]
        XCTAssertTrue(title.isHittable, "The inset title must stay visible above its text field.")
        XCTAssertGreaterThanOrEqual(title.frame.minY, stage.frame.minY)
        XCTAssertGreaterThanOrEqual(bar.frame.minX, stage.frame.minX)
        XCTAssertLessThanOrEqual(bar.frame.maxX, stage.frame.maxX)
        XCTAssertLessThanOrEqual(title.frame.maxY, field.frame.minY)
        capture(app, "SafeAreaInset-keyboard")
        // 真实滚动手势交互式收起；若键盘未消失则作为失败，不伪装成已覆盖。
        // Duo 的 Application.frame 可能仍是另一显示面的尺寸；以当前滚动视口生成手势。
        let startY = min(60, (bar.frame.minY - scroll.frame.minY) / 2)
        let start = scroll.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: scroll.frame.width / 2, dy: startY))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: -20))
        start.press(forDuration: 0.1, thenDragTo: end)
        let keyboardHidden = NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists || app.keyboards.firstMatch.frame.intersection(stage.frame).height < 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: keyboardHidden, object: nil)], timeout: 5), .completed)
        XCTAssertEqual(field.frame.maxY, initialY, accuracy: 1)
        capture(app, "SafeAreaInset-keyboard-dismissed")
    }

    @MainActor private func verifyScenarios(locale: String, titles: [String]) throws {
        let app = openPage(locale: locale)
        let scroll = app.scrollViews["safeAreaInset.scroll"]
        let stage = app.otherElements["safeAreaInset.stage"]
        for (index, title) in titles.enumerated() {
            select(title, in: app)
            XCTAssertEqual(scroll.frame.minY, stage.frame.minY, accuracy: 1)
            // stage 表示默认安全区内的内容区域，滚动外框恢复至窗口底部；不能再要求二者等高。
            XCTAssertEqual(scroll.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1)
            XCTAssertGreaterThanOrEqual(scroll.frame.maxY, stage.frame.maxY)
            let last = app.staticTexts["safeAreaInset.row.24"]
            for _ in 0..<14 {
                if last.isHittable && last.frame.maxY <= visibleBottom(in: app, index: index, scroll: scroll) + 1 { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(last.isHittable, title)
            XCTAssertLessThanOrEqual(last.frame.maxY, visibleBottom(in: app, index: index, scroll: scroll) + 1, title)
            capture(app, "SafeAreaInset-\(locale)-\(index)")
        }
    }
    @MainActor private func visibleBottom(in app: XCUIApplication, index: Int, scroll: XCUIElement) -> CGFloat {
        [0, 4, 5, 6].contains(index) ? app.otherElements["safeAreaInset.primary"].frame.minY : app.otherElements["safeAreaInset.stage"].frame.maxY
    }
    @MainActor private func select(_ title: String, in app: XCUIApplication) {
        app.buttons["safeAreaInset.scenario"].tap()
        let option = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", title, "safeAreaInset.scenario")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }
    @MainActor private func openPage(locale: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        let route = app.cells["demo.safeAreaInset.title"]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<8 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        XCTAssertTrue(app.buttons["safeAreaInset.scenario"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
