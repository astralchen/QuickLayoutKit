import XCTest

/// 从真实菜单进入不同滚动实现，检查旋转、滚动和指示器的公共可访问几何。
final class ScrollPageSafeAreaAuditUITests: XCTestCase {
    @MainActor func testNativeCollectionPage() { verify(route: "demo.contentConfiguration.collection.title", search: "Collection") }
    @MainActor func testNativeTablePage() { verify(route: "demo.contentConfiguration.table.title", search: "Table") }
    @MainActor func testDynamicPage() { verify(route: "demo.dynamicScroll.title", search: "Dynamic") }
    @MainActor func testFormPage() { verify(route: "demo.form.title", search: "Form") }
    @MainActor func testContentMarginsPage() { verify(route: "demo.contentMargins.title", search: "Margins") }
    @MainActor func testNestedGeometryPage() { verify(route: "demo.geometry.title", search: "Geometry") }

    /// 在同一导航栈和设备上比较系统指示器可拖动区域，分别覆盖两种横屏方向。
    @MainActor func testDynamicIndicatorMatchesSwiftUIAcrossRotation() throws {
        try verifyDynamicIndicator(.english)
    }

    @MainActor func testDynamicIndicatorMatchesSwiftUIAcrossRotationInRTL() throws {
        try verifyDynamicIndicator(.arabic)
    }

    /// 系统语言为英文时，通过应用菜单切换到阿拉伯语，再进入动态滚动页。
    @MainActor func testDynamicIndicatorAfterSwitchingToRTL() throws {
        try verifyDynamicIndicator(.switchToArabic)
    }

    private enum LanguageScenario {
        case english, arabic, switchToArabic
    }

    @MainActor private func verifyDynamicIndicator(_ language: LanguageScenario) throws {
        let rtl = language != .english
        guard #available(iOS 17.0, *) else { throw XCTSkip("系统对照需要 contentMargins") }
        continueAfterFailure = false
        defer { XCUIDevice.shared.orientation = .portrait }
        var reference: [UIDeviceOrientation: (track: CGRect, card: CGRect)] = [:]
        for isReference in [true, false] {
            XCUIDevice.shared.orientation = .portrait
            let app = open(route: "demo.dynamicScroll.title", search: rtl ? "ديناميكي" : "Dynamic", language: language,
                           arguments: isReference ? ["-dynamic-scroll-swiftui-reference"] : [])
            let scroll = app.scrollViews.firstMatch
            let first = scroll.descendants(matching: .any)[isReference ? "reference.item.0" : "dynamic.item.0"]
            let action = app.descendants(matching: .any)[isReference ? "reference.add" : "dynamic.addButton"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
                XCUIDevice.shared.orientation = orientation
                let window = app.windows.firstMatch
                // 两种横屏互换时宽高相同，旋转动画中滚动视图仍可能带有临时变换。
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let frame = window.frame
                    return (orientation == .portrait ? frame.height > frame.width : frame.width > frame.height)
                        && scroll.frame == frame
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
                for _ in 0..<3 where !first.isHittable { scroll.swipeDown() }
                XCTAssertTrue(first.isHittable)
                let card = first.frame
                // 顶部按钮位于 trailing，实测它所在的一侧，防止两页误以 LTR 运行。
                XCTAssertTrue(action.exists)
                XCTAssertEqual(action.frame.midX < window.frame.midX, rtl)
                let lower = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.68))
                let upper = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.32))
                lower.press(forDuration: 0.05, thenDragTo: upper)
                capture("dynamic-\(rtl ? "rtl" : "ltr")-\(isReference ? "swiftui" : "kit")-\(orientation.rawValue)")
                XCTAssertTrue(!first.isHittable || first.frame.midY < card.midY - 12)
                let indicator = scroll.descendants(matching: .any).matching(
                    NSPredicate(format: "label BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS %@",
                                "Vertical scroll bar", "شريط التمرير", "شريط تمرير")).firstMatch
                XCTAssertTrue(indicator.waitForExistence(timeout: 5), scroll.debugDescription)
                let track = indicator.frame
                XCTAssertGreaterThan(track.height, track.width)
                XCTAssertEqual(track.midX < window.frame.midX, rtl)
                print("DynamicIndicator rtl=\(rtl) reference=\(isReference) orientation=\(orientation.rawValue) card=\(card) track=\(track)")
                if isReference {
                    reference[orientation] = (track, card)
                } else {
                    let expected = try XCTUnwrap(reference[orientation])
                    XCTAssertEqual(card.minX, expected.card.minX, accuracy: 1)
                    XCTAssertEqual(card.maxX, expected.card.maxX, accuracy: 1)
                    XCTAssertEqual(track.midX, expected.track.midX, accuracy: 1)
                    XCTAssertEqual(track.minY, expected.track.minY, accuracy: 1)
                    XCTAssertEqual(track.maxY, expected.track.maxY, accuracy: 1)
                }
                scroll.swipeDown()
            }
            app.terminate()
        }
    }

    /// 纵向页面嵌套横向卡片时，两层滚动分别响应；旋转不能累加横向安全区。
    @MainActor func testNestedHorizontalCarousel() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = open(route: "demo.horizontalScroll.title", search: "Horizontal")
        let first = app.buttons["horizontal.destination.lakeside"]
        let last = app.buttons["horizontal.destination.coast"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let initialWidth = first.frame.width
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let window = app.windows.firstMatch
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                orientation == .portrait ? window.frame.height > window.frame.width : window.frame.width > window.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            let visible = first.frame.intersection(window.frame.insetBy(dx: 0, dy: 75))
            XCTAssertFalse(visible.isNull)
            // 宽窗口可能同时显示目录，往返手势都要从详情列内发出。
            let entry = app.cells["demo.horizontalScroll.title"]
            let detailStart = entry.exists && entry.isHittable ? entry.frame.maxX + 20 : window.frame.minX
            let detailWidth = window.frame.maxX - detailStart
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let left = origin.withOffset(CGVector(dx: detailStart + detailWidth * 0.18, dy: visible.midY))
            let right = origin.withOffset(CGVector(dx: detailStart + detailWidth * 0.82, dy: visible.midY))
            for _ in 0..<8 where !last.isHittable || last.frame.maxX > window.frame.maxX - 16 {
                right.press(forDuration: 0.05, thenDragTo: left)
            }
            capture("carousel-\(orientation.rawValue)-last")
            XCTAssertTrue(last.isHittable)
            XCTAssertLessThanOrEqual(last.frame.maxX, window.frame.maxX - 15)
            for _ in 0..<8 where !first.isHittable || first.frame.minX < 15 {
                left.press(forDuration: 0.05, thenDragTo: right)
            }
            XCTAssertTrue(first.isHittable)
            XCTAssertGreaterThanOrEqual(first.frame.minX, 15)
            if orientation == .portrait { XCTAssertEqual(first.frame.width, initialWidth, accuracy: 1) }
        }
    }

    @MainActor private func verify(route: String, search: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = open(route: route, search: search)
        let scroll: XCUIElement
        if route == "demo.contentConfiguration.table.title" { scroll = app.tables.firstMatch }
        else if route == "demo.contentConfiguration.collection.title" { scroll = app.collectionViews.firstMatch }
        else { scroll = app.scrollViews.firstMatch }
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            let window = app.windows.firstMatch.frame
            XCTAssertEqual(scroll.frame.width, window.width, accuracy: 1, route)
            if route == "demo.contentMargins.title" {
                let preview = app.scrollViews["contentMargins.preview"]
                let metrics = app.staticTexts["contentMargins.metrics"]
                XCTAssertEqual(preview.frame.height, 360, accuracy: 1)
                XCTAssertGreaterThanOrEqual(preview.frame.minY, metrics.frame.maxY + 11)
            }
            scroll.swipeUp()
            capture("\(route)-\(orientation.rawValue)-scrolled")
            let indicator = scroll.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar")).firstMatch
            if indicator.exists {
                // 本轮设备为 iPhone 18 Pro，允许显式 margins；重复侧边安全区会明显退入内容。
                XCTAssertGreaterThan(indicator.frame.midX, scroll.frame.maxX - scroll.frame.width * 0.14, route)
                XCTAssertLessThanOrEqual(indicator.frame.maxY, window.maxY + 1, route)
            }
            scroll.swipeDown()
        }
    }

    @MainActor private func open(route: String, search: String, language: LanguageScenario = .english, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let startsInArabic = language == .arabic
        app.launchArguments = ["-AppleLanguages", startsInArabic ? "(ar)" : "(en)",
                               "-quicklayoutkit.demo.locale.identifier", startsInArabic ? "ar" : "en-US"] + arguments
        app.launch()
        if language == .switchToArabic {
            let menu = app.buttons.matching(identifier: "demo.language.menu").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "العربية")).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
        }
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(search)
        let entry = app.cells[route]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        return app
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
