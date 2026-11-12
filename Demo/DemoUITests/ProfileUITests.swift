import XCTest

/// 验证资料页在真实导航窗口中的滚动方向及内容可达性。
final class ProfileUITests: XCTestCase {
    /// 左右横屏后真实滚动，检查垂直指示器仍位于视口边缘，而不是退入卡片内容中。
    @MainActor func testScrollIndicatorStaysNearViewportEdgeAcrossRotation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let route = app.cells["demo.profile.title"]
        for _ in 0..<8 where !route.isHittable { app.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            scroll.swipeUp()
            // 手势结束后立即取图，避免等待可访问元素时系统指示器已经淡出。
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "profile-indicator-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let indicator = scroll.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar")).firstMatch
            XCTAssertTrue(indicator.waitForExistence(timeout: 3), app.debugDescription)
            print("Indicator orientation=\(orientation.rawValue) scroll=\(scroll.frame) indicator=\(indicator.frame)")
            // 此用例使用 iPhone 18 Pro；横屏侧边安全区小于视口宽度的 10%，重复补偿会越界。
            XCTAssertGreaterThan(indicator.frame.midX, scroll.frame.maxX - scroll.frame.width * 0.1)
        }
    }

    /// 中文资料页应保持横向位置，并允许滚动至底部操作区。
    @MainActor func testChineseProfileScrollsOnlyVertically() {
        verifyScrolling(locale: "zh-Hans", name: "张三", portfolio: "作品集")
    }

    /// RTL 资料页使用相同的滚动约束与安全区边距。
    @MainActor func testArabicProfileScrollsOnlyVertically() {
        verifyScrolling(locale: "ar", name: "جون دو", portfolio: "معرض الأعمال")
    }

    /// 左右拖动后检查内容位置，再确认纵向手势仍可到达底部按钮。
    @MainActor private func verifyScrolling(locale: String, name: String, portfolio: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))",
                               "-quicklayoutkit.demo.locale.identifier", locale,
                               "-profile-scroll-probe"]
        app.launch()
        let route = app.cells["demo.profile.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let scroll = app.scrollViews.firstMatch
        let label = scroll.staticTexts[name]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        print("Profile viewport: \(app.frame), scroll: \(scroll.frame)")
        capture(app, "资料页-\(locale)-首次展示")
        let initialFrame = label.frame
        // 以资料卡中的姓名为中心，避免从屏幕边缘触发系统返回手势。
        let center = label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let left = center.withOffset(CGVector(dx: -80, dy: 0))
        let right = center.withOffset(CGVector(dx: 80, dy: 0))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 3)
        XCTAssertEqual(label.frame.minX, initialFrame.minX, accuracy: 1)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 3)
        XCTAssertEqual(label.frame.minX, initialFrame.minX, accuracy: 1)
        assertNoHorizontalMovementDuringDrag(scroll)
        capture(app, "资料页-\(locale)-左右拖动后")
        // 同时覆盖带水平分量的纵向拖动，避免纯水平手势未启动滚动而漏检。
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.7))
            .press(forDuration: 0.05,
                   thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        assertNoHorizontalMovementDuringDrag(scroll)
        scroll.swipeUp()
        // Duo 宽屏中文内容仅略高于视口；不要求人为固定的最小滚动距离。
        XCTAssertLessThan(label.frame.minY, initialFrame.minY - 1)
        let button = scroll.buttons[portfolio]
        for _ in 0..<5 where !button.isHittable { scroll.swipeUp() }
        XCTAssertTrue(button.isHittable)
        assertNoHorizontalMovementDuringDrag(scroll)
        capture(app, "资料页-\(locale)-底部操作区")
    }

    /// 应用侧记录整段手势的最大位移，包含按住不放和松手减速过程。
    @MainActor private func assertNoHorizontalMovementDuringDrag(_ scroll: XCUIElement) {
        guard let value = scroll.value as? String, let maximum = Double(value) else {
            XCTFail("未取得资料页拖动过程的横向位移记录")
            return
        }
        print("Profile horizontal displacement during drag: \(maximum) pt")
        XCTAssertLessThanOrEqual(maximum, 1, "拖动过程中最大横向位移为 \(maximum) 点")
    }

    /// 保留首屏、横向拖动和底部内容的模拟器截图。
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
