import XCTest

final class HorizontalScrollUITests: XCTestCase {
    @MainActor func testCompactCarousel() throws {
        try verifyRotation(locale: "zh-Hans", rtl: false, rotates: false)
    }

    @MainActor func testIPadCarouselAdaptsToRotation() throws {
        try verifyRotation(locale: "zh-Hans", rtl: false)
    }

    @MainActor func testIPadRTLCarouselAdaptsToRotation() throws {
        try verifyRotation(locale: "ar", rtl: true)
    }

    @MainActor private func verifyRotation(locale: String, rtl: Bool, rotates: Bool = true) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))",
                               "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        let route = app.cells["demo.horizontalScroll.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let first = app.buttons["horizontal.destination.lakeside"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        verifyCards(in: app, rtl: rtl)
        capture(app, "carousel-\(locale)-portrait")

        if rotates {
            let portraitSize = app.windows.firstMatch.frame.size
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.windows.firstMatch.frame.size != portraitSize
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
            verifyCards(in: app, rtl: rtl)
            capture(app, "carousel-\(locale)-landscape")
        }

        // 从卡片内部拖动，验证后面的目的地仍然可达。
        let last = app.buttons["horizontal.destination.coast"]
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: window.frame.width * (rtl ? 0.2 : 0.8), dy: first.frame.midY))
        let end = origin.withOffset(CGVector(dx: window.frame.width * (rtl ? 0.8 : 0.2), dy: first.frame.midY))
        // 等分宽度在像素对齐后可产生不足 1 pt 的舍入误差。
        let visibleBounds = window.frame.insetBy(dx: 15, dy: 0)
        for _ in 0..<5 where !visibleBounds.contains(last.frame) {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(visibleBounds.contains(last.frame), "last=\(last.frame), visible=\(visibleBounds)")
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor private func verifyCards(in app: XCUIApplication, rtl: Bool) {
        let first = app.buttons["horizontal.destination.lakeside"]
        let second = app.buttons["horizontal.destination.bamboo"]
        let width = app.windows.firstMatch.frame.width - 32
        // 根据实际可见卡片验证最小宽度和最大宽度，覆盖不同尺寸的 iPad。
        let identifiers = ["lakeside", "bamboo", "city", "garden", "coast"]
        let frames = identifiers.map { app.buttons["horizontal.destination.\($0)"].frame }
        let trailingEdge = app.windows.firstMatch.frame.maxX - 16
        let count = frames.filter { $0.minX >= 15 && $0.maxX <= trailingEdge + 1 }.count
        print("CAROUSEL window=\(app.windows.firstMatch.frame) cards=\(frames) visibleCount=\(count)")
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThan(count, frames.count)
        // 再放入一张完整卡片将低于最小宽度；当前排列已充分利用可用宽度。
        XCTAssertGreaterThan(CGFloat(count + 1) * (280 + 16) + 32, width)
        XCTAssertGreaterThanOrEqual(first.frame.width, 280)
        XCTAssertLessThanOrEqual(first.frame.width, 360)
        let preview = rtl ? frames[count].maxX - 16 : trailingEdge - frames[count].minX
        XCTAssertGreaterThanOrEqual(preview, 31)
        if first.frame.width < 359 {
            XCTAssertEqual(preview, 32, accuracy: 1)
        }
        let spacing = rtl ? first.frame.minX - second.frame.maxX : second.frame.minX - first.frame.maxX
        XCTAssertEqual(spacing, 16, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        XCTAssertGreaterThan(first.frame.height, 146)
        XCTAssertTrue(second.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
