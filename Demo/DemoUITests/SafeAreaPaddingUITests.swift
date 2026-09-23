import XCTest

/// 在真实导航窗口中核对安全区 API、场景切换及内容可达性。
final class SafeAreaPaddingUITests: XCTestCase {
    @MainActor func testAllScenariosLTR() throws {
        try verifyAllScenarios(locale: "zh-Hans", rtl: false)
    }

    @MainActor func testAllScenariosRTL() throws {
        try verifyAllScenarios(locale: "ar", rtl: true)
    }

    @MainActor func testRotationUpdatesSafeArea() throws {
        let app = openPage(locale: "zh-Hans")
        defer { XCUIDevice.shared.orientation = .portrait }
        let original = app.windows.firstMatch.frame.size
        XCUIDevice.shared.orientation = original.width > original.height ? .portrait : .landscapeLeft
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.size != original
        }, object: app)
        guard XCTWaiter.wait(for: [changed], timeout: 8) == .completed else {
            capture(app, "安全区-旋转请求后窗口未变")
            let sidebarBack = app.buttons["BackButton"]
            let back = sidebarBack.exists ? sidebarBack : app.navigationBars.buttons
                .matching(NSPredicate(format: "identifier != %@", "demo.language.menu")).firstMatch
            back.tap()
            XCTAssertTrue(app.cells["demo.safeAreaPadding.title"].waitForExistence(timeout: 5))
            XCUIDevice.shared.orientation = .landscapeRight
            let mainChanged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.windows.firstMatch.frame.size != original
            }, object: app)
            let mainResponded = XCTWaiter.wait(for: [mainChanged], timeout: 5) == .completed
            capture(app, "首页-旋转对照")
            app.cells["demo.safeAreaPadding.title"].tap()
            XCTAssertTrue(app.staticTexts["safeAreaPadding.metrics"].waitForExistence(timeout: 5))
            if mainResponded {
                XCTFail("首页可旋转，但安全区页面未响应旋转")
                return
            }
            throw XCTSkip("Duo 首页和安全区页面均未响应 XCUIDevice 旋转请求；不将其计为旋转通过")
        }
        try verifyScenarios(in: app, rtl: false)
    }

    @MainActor private func verifyAllScenarios(locale: String, rtl: Bool) throws {
        try verifyScenarios(in: openPage(locale: locale), rtl: rtl)
    }

    @MainActor private func openPage(locale: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))",
                               "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        let route = app.cells["demo.safeAreaPadding.title"]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<10 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        XCTAssertTrue(app.staticTexts["safeAreaPadding.metrics"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func verifyScenarios(in app: XCUIApplication, rtl: Bool) throws {
        let titles = ["No modifier", ".all · 0", ".all · nil", ".all · 16",
                      ".horizontal · 16", "EdgeInsets", "horizontal + bottom",
                      "leading 8 + leading 12", "leading 8 + nil", "negative leading"]
        let page = app.scrollViews["safeAreaPadding.page"]
        let selector = app.buttons["safeAreaPadding.scenario"]
        let baseline = try metrics(in: app)
        let root = CGRect(x: baseline[4], y: baseline[5], width: baseline[6], height: baseline[7])
        let origin = page.frame.origin
        for (index, title) in titles.enumerated() {
            if index > 0 {
                selector.tap()
                let option = app.buttons[title]
                XCTAssertTrue(option.waitForExistence(timeout: 3), title)
                option.tap()
            }
            XCTAssertTrue(selector.label.contains("\(index + 1)/10"))
            let m = try metrics(in: app)
            let top = m[0], left = m[1], bottom = m[2], right = m[3]
            let leading = rtl ? right : left
            let insets: [CGFloat]
            switch index {
            case 0: insets = [0, 0, 0, 0]
            case 1, 2: insets = [top, left, bottom, right]
            case 3: insets = [top + 16, left + 16, bottom + 16, right + 16]
            case 4: insets = [0, left + 16, 0, right + 16]
            case 5: insets = [top + 8, left + (rtl ? 24 : 12), bottom + 20, right + (rtl ? 12 : 24)]
            case 6: insets = [0, left + 16, bottom + 24, right + 16]
            default:
                let extra: CGFloat = index == 7 ? 20 : index == 8 ? 8 : 0
                insets = [0, rtl ? 0 : leading + extra, 0, rtl ? leading + extra : 0]
            }
            let expected = root.inset(by: UIEdgeInsets(top: insets[0], left: insets[1], bottom: insets[2], right: insets[3]))
            let actual = CGRect(x: m[4], y: m[5], width: m[6], height: m[7])
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 1, title)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 1, title)
            XCTAssertEqual(actual.width, expected.width, accuracy: 1, title)
            XCTAssertEqual(actual.height, expected.height, accuracy: 1, title)
            // 同时检查 AX 实际滚动容器，避免只验证页面自身打印的字符串。
            XCTAssertEqual(page.frame.minX - origin.x, expected.minX, accuracy: 1, title)
            XCTAssertEqual(page.frame.minY - origin.y, expected.minY, accuracy: 1, title)
            XCTAssertEqual(page.frame.width, expected.width, accuracy: 1, title)
            XCTAssertEqual(page.frame.height, expected.height, accuracy: 1, title)
            XCTAssertTrue(app.staticTexts["safeAreaPadding.metrics"].label.contains(rtl ? "RTL" : "LTR"))
            XCTAssertTrue(selector.isHittable)
            print("SAFE_AREA \(rtl ? "RTL" : "LTR") \(title): \(app.staticTexts["safeAreaPadding.metrics"].label)")
            capture(app, "安全区-\(rtl ? "RTL" : "LTR")-\(index + 1)")
        }
        page.swipeUp()
        page.swipeUp()
        XCTAssertTrue(page.staticTexts["Safe area content 8"].isHittable)
        capture(app, "安全区-\(rtl ? "RTL" : "LTR")-滚动到底部")
    }

    @MainActor private func metrics(in app: XCUIApplication) throws -> [CGFloat] {
        let text = app.staticTexts["safeAreaPadding.metrics"].label
        let regex = try NSRegularExpression(pattern: "-?[0-9]+")
        let values = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> CGFloat? in
            guard let range = Range(match.range, in: text), let value = Double(text[range]) else { return nil }
            return CGFloat(value)
        }
        XCTAssertEqual(values.count, 8, text)
        guard values.count == 8 else { throw NSError(domain: "SafeAreaMetrics", code: 1) }
        return values
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
