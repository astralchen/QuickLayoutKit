import XCTest

/// 从真实入口旋转，验证首屏卡片没有被推到视口外，返回竖屏后仍可操作。
final class WaterfallRotationUITests: XCTestCase {
    /// 横向内容滚动与设备旋转分别验证，防止仅切换设备方向而遗漏 Horizontal 模式。
    @MainActor func testHorizontalModeFitsAfterRotationAndScrolling() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let route = app.cells["demo.contentConfiguration.waterfall.title"]
        for _ in 0..<10 where !route.isHittable { app.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let controls = app.segmentedControls["waterfall.direction"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        controls.buttons["Horizontal"].tap()
        for (index, orientation) in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight].enumerated() {
            XCUIDevice.shared.orientation = orientation
            let window = app.windows.firstMatch
            let first = app.cells["waterfall.cell.0"]
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = window.frame
                return (orientation == .portrait ? frame.height > frame.width : frame.width > frame.height)
                    && first.exists && first.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let y = max(controls.frame.maxY + 35, first.frame.midY)
            let left = origin.withOffset(CGVector(dx: window.frame.width * 0.25, dy: y))
            let right = origin.withOffset(CGVector(dx: window.frame.width * 0.75, dy: y))
            right.press(forDuration: 0.05, thenDragTo: left)
            for _ in 0..<6 {
                left.press(forDuration: 0.05, thenDragTo: right)
                if first.exists && first.isHittable { break }
            }
            XCTAssertTrue(first.exists && first.isHittable)
            XCTAssertLessThanOrEqual(first.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
            XCTAssertTrue(first.frame.contains(first.staticTexts["Moonlight Note"].frame))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "waterfall-horizontal-\(index)-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor func testRotationKeepsFirstCardsVisible() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let route = app.cells["demo.contentConfiguration.waterfall.title"]
        for _ in 0..<10 where !route.isHittable { app.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        XCTAssertTrue(app.segmentedControls["waterfall.direction"].waitForExistence(timeout: 5))
        var initialPortraitSize: CGSize?
        for (index, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait, .landscapeRight, .portrait].enumerated() {
            XCUIDevice.shared.orientation = orientation
            let window = app.windows.firstMatch
            let first = app.cells["waterfall.cell.0"]
            let controls = app.segmentedControls["waterfall.direction"]
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = window.frame
                return (orientation == .portrait ? frame.height > frame.width : frame.width > frame.height)
                    && frame.contains(controls.frame)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            if index > 0 {
                // 旋转后真实滚动会触发单元格复用和新的自适应测量。
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let top = origin.withOffset(CGVector(dx: window.frame.midX, dy: controls.frame.maxY + 45))
                let bottom = origin.withOffset(CGVector(dx: window.frame.midX, dy: window.frame.maxY - 95))
                bottom.press(forDuration: 0.05, thenDragTo: top)
                for _ in 0..<8 {
                    top.press(forDuration: 0.05, thenDragTo: bottom)
                    if first.exists && first.frame.minY > controls.frame.maxY { break }
                }
            }
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                first.exists && first.frame.minY < window.frame.maxY - 90
                    && first.frame.maxY > controls.frame.maxY && first.isHittable
            }, object: nil)
            let result = XCTWaiter.wait(for: [visible], timeout: 5)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "waterfall-rotation-\(index)-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(result, .completed, "首个项目：\(first.exists ? first.frame : .null)，窗口：\(window.frame)，控件：\(controls.frame)")
            if orientation == .portrait {
                // 返回同一容器宽度后，自适应高度也应恢复，不能残留横屏的内容约束。
                if let initialPortraitSize {
                    XCTAssertEqual(first.frame.width, initialPortraitSize.width, accuracy: 1)
                    XCTAssertEqual(first.frame.height, initialPortraitSize.height, accuracy: 1)
                } else {
                    initialPortraitSize = first.frame.size
                }
                XCTAssertTrue(window.frame.contains(first.staticTexts["Moonlight Note"].frame))
            }
        }
        let first = app.cells["waterfall.cell.0"]
        first.tap()
        XCTAssertTrue(first.isHittable)
    }
}
