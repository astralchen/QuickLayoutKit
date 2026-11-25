import XCTest

final class OverPresentationUITests: XCTestCase {
    @MainActor func testLTRPresentationAndGestures() {
        exercise(locale: "zh-Hans", trailingOnRight: true)
    }

    @MainActor func testRTLPresentationAndGestures() {
        exercise(locale: "ar", trailingOnRight: false)
    }

    @MainActor private func exercise(locale: String, trailingOnRight: Bool) {
        continueAfterFailure = false
        let previousOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = previousOrientation }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        let route = app.cells["demo.overPresentation.title"]
        let catalog = app.collectionViews.firstMatch
        XCTAssertTrue(catalog.waitForExistence(timeout: 8))
        for _ in 0..<8 where !route.isHittable { catalog.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let open = app.buttons["over.open"]
        let menu = app.tables["over.menu"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["over.gallery.title"].isHittable)
        let profile = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        profile.name = "FieldNotes-Profile-\(locale)"
        profile.lifetime = .keepAlways
        add(profile)
        let original = open.frame
        let window = app.windows.firstMatch
        let width = window.frame.width
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: trailingOnRight ? fraction : 1 - fraction, dy: 0.55))
        }
        func drag(_ from: CGFloat, _ to: CGFloat) {
            point(from).press(forDuration: 0.08, thenDragTo: point(to), withVelocity: .slow, thenHoldForDuration: 0.25)
        }

        open.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        let panelFraction = menu.frame.width / width
        XCTAssertGreaterThan(panelFraction, 0)
        XCTAssertLessThan(panelFraction, 1)
        XCTAssertEqual(menu.frame.minX, trailingOnRight ? window.frame.maxX - menu.frame.width : window.frame.minX, accuracy: 2)
        let close = app.buttons["over.close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        if let status = app.statusBars.allElementsBoundByIndex.first {
            XCTAssertGreaterThanOrEqual(close.frame.minY, status.frame.maxY - 1)
        }
        let openedFrame = menu.frame
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "OverPresentation-\(locale)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 4))
        open.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        // 以实际展开宽度计算手势行程，覆盖紧凑窗口与半屏侧栏的取消和完成路径。
        let insidePanel = 1 - 0.85 * panelFraction
        drag(insidePanel, insidePanel + 0.12 * panelFraction)
        XCTAssertEqual(menu.frame, openedFrame)
        point((1 - panelFraction) / 2).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 4))
        XCTAssertEqual(open.frame.minX, original.minX, accuracy: 1)

        drag(0.998, 1 - 0.18 * panelFraction)
        XCTAssertFalse(menu.exists)
        XCTAssertTrue(open.isHittable)
        drag(0.998, 1 - 0.94 * panelFraction)
        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        XCTAssertEqual(menu.frame, openedFrame)
        drag(insidePanel, 1 - 0.08 * panelFraction)
        XCTAssertTrue(menu.waitForNonExistence(timeout: 4))
        XCTAssertTrue(open.isHittable)

        // 侧栏选择改变主页作品集合；点缩略图应打开当前相册中的原图。
        open.tap()
        app.cells["over.album.lakes"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 4))
        let lake = app.buttons["over.photo.lake"]
        XCTAssertTrue(lake.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["over.photo.ridge"].exists)
        lake.tap()
        let previewTitle = trailingOnRight ? "湖畔木屋" : "كوخ البحيرة"
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", previewTitle))
            .firstMatch.waitForExistence(timeout: 6))
    }
}
