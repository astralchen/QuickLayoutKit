import XCTest

final class LocalizedControlUITests: XCTestCase {
    @MainActor func testPositionMirrorsAcrossLanguageChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "ar"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.positionAndZIndex.title"]
        for _ in 0..<12 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        for (index, language) in ["العربية", "English", "العربية"].enumerated() {
            if index > 0 {
                app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
                let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
            }
            let rtl = language == "العربية"
            for labels in [["A (60, 54)", "B (144, 100)", "C (228, 146)"],
                           ["A zIndex(0)", "B zIndex(3)", "C zIndex(1)"]] {
                let cards = labels.map { app.staticTexts[$0] }
                XCTAssertTrue(cards[0].waitForExistence(timeout: 5))
                XCTAssertTrue(cards[1].exists && cards[2].exists)
                XCTAssertTrue(rtl ? cards[0].frame.midX > cards[1].frame.midX : cards[0].frame.midX < cards[1].frame.midX)
                XCTAssertTrue(rtl ? cards[1].frame.midX > cards[2].frame.midX : cards[1].frame.midX < cards[2].frame.midX)
            }
            if index == 0 { app.scrollViews.firstMatch.swipeUp() }
            // Duo 的实际显示面由外部 simctl 捕获，避免默认显示面的空白截图。
            print("POSITION-CAPTURE-\(index)")
            Thread.sleep(forTimeInterval: 2)
        }
    }

    @MainActor func testUIKitShowcaseLeadingAcrossLanguageChanges() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "ar"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.uikitLocalization.title"]
        for _ in 0..<20 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let collection = app.collectionViews["uikitLocalization.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        for (index, language) in ["العربية", "English", "العربية"].enumerated() {
            if index > 0 {
                app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
                let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
            }
            let rtl = language == "العربية"
            let first = collection.cells.containing(.staticText, identifier: rtl ? "عنصر 1" : "Item 1").firstMatch
            let last = collection.cells.containing(.staticText, identifier: rtl ? "عنصر 3" : "Item 3").firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(last.exists)
            XCTAssertGreaterThan(collection.frame.width, 420)
            XCTAssertLessThan(abs(rtl ? first.frame.maxX - collection.frame.maxX : first.frame.minX - collection.frame.minX), 2)
            XCTAssertTrue(rtl ? first.frame.minX > last.frame.minX : first.frame.minX < last.frame.minX)
            // Duo 的 XCTest 截图只读取默认显示面；由外部 simctl 捕获实际显示面。
            print("SHOWCASE-CAPTURE-\(index)")
            Thread.sleep(forTimeInterval: 2)
        }
    }

    @MainActor func testArabicFormCaretAfterTypingAndClearing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "ar"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.form.title"]
        for _ in 0..<16 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let field = app.textFields.element(boundBy: 0)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.placeholderValue, "الاسم")
        field.tap()
        capture("form-caret-empty", app: app)
        field.typeText("433")
        XCTAssertEqual(field.value as? String, "433")
        capture("form-caret-digits", app: app)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        capture("form-caret-cleared", app: app)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testArabicReportedPages() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "ar"]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for name in ["safeAreaInset", "contentMargins", "positionAndZIndex", "viewThatFits", "form"] {
            let route = app.cells["demo.\(name).title"]
            for _ in 0..<12 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(route.isHittable, name)
            route.tap()
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "arabic-fixed-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    @MainActor func testSliderDraggingSurvivesLanguageRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let route = app.cells["demo.viewThatFits.title"]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<8 where !route.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let slider = app.sliders["viewThatFits.width"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        for (index, language) in ["العربية", "简体中文", "English"].enumerated() {
            let menu = app.buttons.matching(identifier: "demo.language.menu").firstMatch
            XCTAssertTrue(menu.exists)
            menu.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            XCTAssertTrue(slider.waitForExistence(timeout: 5))
            drag(slider, to: 0.2, rtl: language == "العربية")
            let firstValue = slider.value as? String
            drag(slider, to: 0.8, rtl: language == "العربية")
            XCTAssertNotEqual(firstValue, slider.value as? String)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "controls-round-trip-\(index)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    @MainActor private func drag(_ slider: XCUIElement, to position: CGFloat, rtl: Bool) {
        // XCTest 的 normalized slider action 在 RTL 中可能使用错误的 thumb 起点。
        // 从原生辅助功能值解析当前位置，直接拖动圆点，覆盖真实触摸路径。
        let digits = String((slider.value as? String ?? "").compactMap { $0.wholeNumberValue }.map(String.init).joined())
        let fraction = CGFloat(Double(digits) ?? 50) / 100
        let origin = slider.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 1 - fraction : fraction, dy: 0.5))
        let target = slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: target)
    }
}
