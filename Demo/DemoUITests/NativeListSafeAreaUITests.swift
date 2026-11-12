import XCTest

/// 操作真实首页列表，验证全屏视口、末行可达和搜索键盘交互。
final class NativeListSafeAreaUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCatalogScrollsBehindBarsAndLastRowRemainsReachable() {
        for locale in ["zh-Hans", "ar"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments += ["-quicklayoutkit.demo.locale.identifier", locale,
                                    "-AppleLanguages", locale == "ar" ? "(ar)" : "(zh-Hans)",
                                    "-chat-draft-session", UUID().uuidString]
            app.launch()
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 10))
            assertFullViewport(list, app: app)
            list.swipeUp()
            capture("首页-滚动中-\(locale)")
            let last = app.cells["demo.localizationBoundary.title"]
            for _ in 0..<16 where !last.isHittable { list.swipeUp() }
            XCTAssertTrue(last.isHittable)
            // 再滚动一次到真正端点，确保整行可见，而非仅露出可点击的一部分。
            list.swipeUp()
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.exists)
            XCTAssertLessThanOrEqual(last.frame.maxY, tabs.frame.minY + 1)
            capture("首页-末行-\(locale)")
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            assertFullViewport(list, app: app)
            capture("首页-横屏-\(locale)")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// 真正旋转并向两个方向拖动列表，检查交叉轴没有滚动范围或残留偏移。
    @MainActor func testCatalogRotationDoesNotAllowHorizontalScrolling() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for locale in ["zh-Hans", "ar"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(locale))", "-quicklayoutkit.demo.locale.identifier", locale]
            app.launch()
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 10))
            for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
                XCUIDevice.shared.orientation = orientation
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let size = app.windows.firstMatch.frame.size
                    return orientation == .portrait ? size.height > size.width : size.width > size.height
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
                assertFullViewport(list, app: app)
                let row = app.cells["demo.safeAreaPadding.title"]
                XCTAssertTrue(row.isHittable)
                let before = row.frame
                // 从分组标题区域拖动，避免无水平滚动时由单元格接收触摸并打开详情。
                let origin = list.coordinate(withNormalizedOffset: .zero)
                let dragY = before.minY - list.frame.minY - 12
                let left = origin.withOffset(CGVector(dx: list.frame.width * 0.25, dy: dragY))
                let right = origin.withOffset(CGVector(dx: list.frame.width * 0.75, dy: dragY))
                for reverse in [false, true] {
                    (reverse ? left : right).press(forDuration: 0.1, thenDragTo: reverse ? right : left)
                    let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        abs(row.frame.minX - before.minX) <= 1 && abs(row.frame.maxX - before.maxX) <= 1
                    }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed,
                                   "locale=\(locale) orientation=\(orientation.rawValue) before=\(before) after=\(row.frame)")
                }
                capture("首页-旋转横拖-\(locale)-\(orientation.rawValue)")
            }
            app.terminate()
        }
    }

    /// RTL 展开目录仅纵向滚动，横拖往返及纵向指示器的位置与同列的 SwiftUI.List 对照。
    @MainActor func testRTLSidebarCrossAxisAndIndicatorMatchSwiftUI() throws {
        var referenceTrack: CGFloat?
        for reference in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(ar)", "-quicklayoutkit.demo.locale.identifier", "ar"]
            if reference { app.launchArguments.append("-catalog-scroll-swiftui-reference") }
            XCUIDevice.shared.orientation = .landscapeLeft
            app.launch()
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
            let window = app.windows.firstMatch.frame
            let viewport = list.frame
            try XCTSkipIf(viewport.width >= window.width * 0.65, "需要展开的双列目录")
            XCTAssertGreaterThan(viewport.midX, window.midX)
            let row = list.descendants(matching: .any).matching(identifier: "demo.safeAreaPadding.title").firstMatch
            XCTAssertTrue(row.exists)
            let before = row.frame
            let left = list.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.47))
            let right = list.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.47))
            for (start, end) in [(left, right), (right, left)] {
                start.press(forDuration: 0.08, thenDragTo: end, withVelocity: 160, thenHoldForDuration: 0.3)
                print("SidebarDrag reference=\(reference) viewport=\(viewport) rowBefore=\(before) after=\(row.frame)")
                XCTAssertEqual(row.frame.minX, before.minX, accuracy: 1)
                XCTAssertEqual(row.frame.maxX, before.maxX, accuracy: 1)
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.47))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 0.3)
            XCTAssertTrue(!row.isHittable || row.frame.minY < before.minY - 12)
            let bars = list.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS %@",
                "Vertical scroll bar", "شريط التمرير", "شريط تمرير"))
            let track = try XCTUnwrap(bars.allElementsBoundByIndex.first { $0.frame.height > $0.frame.width },
                                      list.debugDescription).frame
            let inset = track.midX - viewport.minX
            print("SidebarIndicator reference=\(reference) viewport=\(viewport) track=\(track) fromLeft=\(inset)")
            if reference { referenceTrack = inset }
            else { XCTAssertEqual(inset, try XCTUnwrap(referenceTrack), accuracy: 1) }
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let shot = XCTAttachment(screenshot: screen.screenshot())
                shot.name = "rtl-sidebar-\(reference ? "swiftui" : "kit")-\(index)"
                shot.lifetime = .keepAlways
                add(shot)
            }
            app.terminate()
        }
    }

    @MainActor func testCatalogSearchKeyboardAndClear() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Counter")
        let row = app.cells["demo.counter.title"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(row.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let clear = search.buttons["main.search.clear"]
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("首页-搜索键盘")
        app.collectionViews.firstMatch.swipeDown()
    }

    @MainActor private func assertFullViewport(_ list: XCUIElement, app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(list.frame.minY, window.minY, accuracy: 1)
        XCTAssertEqual(list.frame.maxY, window.maxY, accuracy: 1)
        XCTAssertEqual(list.frame.minX, window.minX, accuracy: 1)
        XCTAssertEqual(list.frame.maxX, window.maxX, accuracy: 1)
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
