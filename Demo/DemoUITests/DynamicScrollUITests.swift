import XCTest

/// 通过应用界面验证动态列表的垂直拖动、边界恢复和项目操作。
///
/// 验证使用 XCTest 合成的触摸手势，并读取辅助功能元素的位置及可交互状态。
final class DynamicScrollUITests: XCTestCase {
    /// 验证三轮顶部至底部往返后，内容位置及悬浮按钮位置可恢复。
    ///
    /// 每轮检查首项确实移动、末项可见，以及继续向底部拖动后位置不再前移。
    /// 返回顶部后比较初始几何值，随后检查新增项目可见、删除后末项仍可交互。
    /// 系统栏收起可能改变安全区域，因此按钮位置按相同滚动端点进行比较。
    ///
    /// - Note: 本测试沿用启动时的设备姿态，不主动旋转设备。
    @MainActor func testRepeatedVerticalDragsKeepOverlayAndReachBothEnds() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-quicklayoutkit.demo.locale.identifier", "en-US",
        ]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Dynamic")
        let route = app.descendants(matching: .any)
            .matching(identifier: "demo.dynamicScroll.title").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()

        let scrollView = app.scrollViews["dynamic.scrollView"]
        let addButton = app.buttons["dynamic.addButton"]
        let first = app.staticTexts["dynamic.item.0.title"]
        let last = app.staticTexts["dynamic.item.9.title"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        let initialFirstFrame = first.frame
        let initialButtonFrame = addButton.frame
        var bottomButtonFrame: CGRect?
        capture(app, "dynamic-initial")
        let lower = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let upper = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))

        for round in 0..<3 {
            lower.press(forDuration: 0.05, thenDragTo: upper)
            XCTAssertLessThan(first.frame.minY, initialFirstFrame.minY - 40)
            for _ in 0..<4 where !last.isHittable {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
            XCTAssertTrue(last.isHittable)
            // 继续向上拖动，确认已到达滚动边界，末项位置不会继续前移。
            lower.press(forDuration: 0.05, thenDragTo: upper)
            let bottomItemY = last.frame.minY
            lower.press(forDuration: 0.05, thenDragTo: upper)
            XCTAssertEqual(last.frame.minY, bottomItemY, accuracy: 1)
            // Duo 的系统导航标题会随滚动收起，安全区域顶部随之改变。
            // 在相同滚动端点比较位置，并确认按钮始终可点，不随列表内容滚出屏幕。
            XCTAssertTrue(addButton.isHittable)
            XCTAssertEqual(addButton.frame.minX, initialButtonFrame.minX, accuracy: 1)
            if let bottomButtonFrame {
                XCTAssertEqual(addButton.frame.minY, bottomButtonFrame.minY, accuracy: 1)
            } else {
                bottomButtonFrame = addButton.frame
            }
            capture(app, "dynamic-bottom-\(round)")

            for _ in 0..<5 {
                upper.press(forDuration: 0.05, thenDragTo: lower)
                if abs(first.frame.minY - initialFirstFrame.minY) < 1 { break }
            }
            XCTAssertTrue(first.isHittable)
            XCTAssertEqual(first.frame.minY, initialFirstFrame.minY, accuracy: 1)
            XCTAssertEqual(addButton.frame.minY, initialButtonFrame.minY, accuracy: 1)
            capture(app, "dynamic-top-\(round)")
        }

        addButton.tap()
        let added = app.staticTexts["dynamic.item.10.title"]
        XCTAssertTrue(added.waitForExistence(timeout: 3))
        XCTAssertTrue(added.isHittable)
        app.buttons["dynamic.item.10.deleteButton"].tap()
        XCTAssertFalse(added.exists)
        XCTAssertTrue(last.isHittable)
    }

    /// 将当前滚动视图、首末项及悬浮按钮的屏幕几何值保存为测试附件。
    ///
    /// 附件在测试成功时也保留，用于比较不同滚动端点的实际位置。
    ///
    /// - Parameters:
    ///   - app: 包含动态滚动页面的目标应用。
    ///   - name: 标识当前滚动阶段的附件名称。
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // Duo 的 app.screenshot() 可能返回未点亮的另一块屏幕，保存实际交互元素几何值。
        let attachment = XCTAttachment(string: """
        scroll: \(app.scrollViews["dynamic.scrollView"].frame)
        first: \(app.staticTexts["dynamic.item.0.title"].frame)
        last: \(app.staticTexts["dynamic.item.9.title"].frame)
        addButton: \(app.buttons["dynamic.addButton"].frame)
        """)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
