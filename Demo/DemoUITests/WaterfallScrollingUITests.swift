import XCTest

final class WaterfallScrollingUITests: XCTestCase {
    @MainActor
    func testNavigationTransitionsKeepContentAndScrollDirectionStable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-quicklayoutkit.demo.locale.identifier", "zh-Hans",
                               "-waterfall-scroll-diagnostics"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("瀑布流")
        let route = app.cells["demo.contentConfiguration.waterfall.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let collection = app.collectionViews["waterfall.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        var consumed = 0
        var sawCollapse = false
        var sawExpansion = false
        for (step, up) in [true, true, false, true, false, false, true].enumerated() {
            if up { collection.swipeUp(velocity: .fast) } else { collection.swipeDown(velocity: .fast) }
            let value = try XCTUnwrap(collection.value as? String)
            let data = try XCTUnwrap(value.data(using: .utf8))
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let all = try XCTUnwrap(payload["samples"] as? [[Double]])
            let samples = Array(all.dropFirst(consumed))
            consumed = all.count
            XCTAssertGreaterThan(samples.count, 5)
            if let first = samples.first, let last = samples.last {
                if up, first[0] - last[0] > 10 { sawCollapse = true }
                if !up, last[0] - first[0] > 10 { sawExpansion = true }
            }
            let attachment = XCTAttachment(string: String(data: try JSONSerialization.data(withJSONObject: samples), encoding: .utf8)!)
            attachment.name = "Waterfall-\(up ? "Up" : "Down")-\(step)-SafeTop-Inset-AdjustedTop-Offset-EmptyCells"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(samples.allSatisfy { $0[4] == 0 }, "导航栏过渡期间不能出现空内容 cell")
            let customInsets = samples.map { $0[1] }
            XCTAssertLessThanOrEqual((customInsets.max() ?? 0) - (customInsets.min() ?? 0), 1,
                                     "顶部栏动画不应改变工具区自己的 contentInset")
            var extreme = samples.first?[0] ?? 0
            for sample in samples {
                if up {
                    XCTAssertLessThanOrEqual(sample[0], extreme + 4, "单向上滑时顶部栏不能反向展开")
                    extreme = min(extreme, sample[0])
                } else {
                    XCTAssertGreaterThanOrEqual(sample[0], extreme - 4, "单向下滑时顶部栏不能反向收起")
                    extreme = max(extreme, sample[0])
                }
            }
        }
        XCTAssertTrue(sawCollapse, "必须实际覆盖导航栏收起")
        XCTAssertTrue(sawExpansion, "必须实际覆盖导航栏展开")
    }

    @MainActor
    func testCardsSurviveNavigationBarCollapseAndReturnToTop() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("waterfall")
        let route = app.cells["demo.contentConfiguration.waterfall.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let control = app.segmentedControls["waterfall.direction"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let collection = app.collectionViews["waterfall.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        let first = app.descendants(matching: .any)["waterfall.card.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let initialY = control.frame.minY
        collection.swipeUp()
        let collapsedY = control.frame.minY
        XCTAssertLessThan(collapsedY, initialY - 10, "必须实际触发顶部栏收起，才能覆盖本次回归")
        for _ in 0..<3 {
            collection.swipeUp()
            collection.swipeDown()
        }
        for _ in 0..<5 { collection.swipeDown() }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Waterfall-Returned-To-Top"
        attachment.lifetime = .keepAlways
        add(attachment)
        let visibleFirst = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            first.exists && first.isHittable && first.frame.height > 100
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleFirst], timeout: 5), .completed,
                       "回到顶部后卡片内容必须恢复，不能仅剩分区背景")
        XCTAssertGreaterThan(control.frame.minY, collapsedY + 10)
        let visibleCells = collection.cells.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertFalse(visibleCells.isEmpty)
        for cell in visibleCells {
            let id = cell.identifier.replacingOccurrences(of: "waterfall.cell.", with: "")
            XCTAssertTrue(cell.descendants(matching: .any)["waterfall.card.\(id)"].exists,
                          "所有进入屏幕的 cell 都应具有对应卡片内容：\(id)")
        }
    }
}
