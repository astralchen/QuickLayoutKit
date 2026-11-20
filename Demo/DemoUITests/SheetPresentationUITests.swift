import XCTest

final class SheetPresentationUITests: XCTestCase {
    @MainActor func testSheetOptionsRepeatedSelectionAndCancellation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.exists, sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Sheet Presentation")
        app.cells["demo.sheetPresentation.title"].tap()
        let hide = app.buttons["Hide Sidebar"]
        if hide.exists, hide.isHittable { hide.tap() }
        let options = app.buttons["sheet.options"]
        let third = app.buttons["Add 1/3 detent"]
        let content = app.segmentedControls["sheet.initialDetent"]
        for expected in [true, false] {
            options.tap()
            XCTAssertTrue(third.waitForExistence(timeout: 4))
            third.tap()
            options.tap()
            app.buttons["Placement"].tap()
            app.buttons[expected ? "trailing" : "automatic"].tap()
            options.tap()
            XCTAssertTrue(third.waitForExistence(timeout: 4))
            let outsideX: CGFloat = third.frame.midX < content.frame.midX ? 0.98 : 0.02
            content.coordinate(withNormalizedOffset: .init(dx: outsideX, dy: 0.5)).tap()
            XCTAssertTrue(third.waitForNonExistence(timeout: 4))
            app.buttons["sheet.open"].tap()
            let close = app.buttons["sheet.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 4))
            XCTAssertEqual(app.buttons["sheet.third"].exists, expected)
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 4))
        }
    }

    @MainActor func testNativeAndCustomSheetGestures() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Sheet Presentation")
        app.cells["demo.sheetPresentation.title"].tap()

        let open = app.buttons["sheet.open"]
        let close = app.buttons["sheet.close"]
        let list = app.tables["sheet.list"]
        var reference: [CGRect] = []
        for engine in ["UIKit", "QuickLayoutKit"] {
            XCTContext.runActivity(named: engine) { _ in
                app.segmentedControls["sheet.engine"].buttons[engine].tap()
                let initial = app.segmentedControls["sheet.initialDetent"]
                initial.buttons["Medium"].tap()
                open.tap()
                XCTAssertTrue(close.waitForExistence(timeout: 4))
                let medium = list.frame
                @MainActor func dragHeader(_ offset: CGFloat, velocity: XCUIGestureVelocity) {
                    // 从内容顶部开始拖，两个引擎均由相同的屏幕触摸序列驱动。
                    let start = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                        .withOffset(CGVector(dx: 0, dy: -6))
                    start.press(forDuration: 0.12, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                                withVelocity: velocity, thenHoldForDuration: 0.2)
                }
                dragHeader(55, velocity: .slow)
                XCTAssertTrue(close.isHittable)
                XCTAssertEqual(list.frame.minY, medium.minY, accuracy: 2, "取消下拉后回到中档")
                dragHeader(-210, velocity: .fast)
                XCTAssertTrue(app.buttons["sheet.large"].isSelected, "手势完成后应由 delegate 更新选中档位")
                let large = list.frame
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "sheet-example-large-" + engine
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTAssertLessThan(large.minY, medium.minY - 100)
                list.swipeUp()
                XCTAssertFalse(app.cells["sheet.row.0"].isHittable)
                XCTAssertEqual(list.frame.minY, large.minY, accuracy: 2)
                app.buttons["sheet.medium"].tap()
                XCTAssertEqual(list.frame.minY, medium.minY, accuracy: 2)
                app.buttons["sheet.large"].tap()
                XCTAssertEqual(list.frame.minY, large.minY, accuracy: 2)
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 4))
                open.tap()
                dragHeader(medium.height * 0.80, velocity: .fast)
                XCTAssertTrue(close.waitForNonExistence(timeout: 4), "长下拉应完成关闭")
                XCTAssertTrue(open.isHittable)
                initial.buttons["Large"].tap()
                open.tap()
                XCTAssertEqual(list.frame.minY, large.minY, accuracy: 2)
                dragHeader(225, velocity: .fast)
                XCTAssertEqual(list.frame.minY, medium.minY, accuracy: 2)
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 4))
                XCTAssertTrue(open.isHittable)
                print("SHEET_FRAMES \(engine) medium=\(medium) large=\(large)")
                if reference.isEmpty {
                    reference = [medium, large]
                } else {
                    for (actual, native) in zip([medium, large], reference) {
                        XCTAssertEqual(actual.minY, native.minY, accuracy: 3)
                        XCTAssertEqual(actual.width, native.width, accuracy: 3)
                        XCTAssertEqual(actual.maxY, native.maxY, accuracy: 3)
                    }
                }
            }
        }
    }

    @MainActor func testUndimmedBackgroundAndScrollPolicy() {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Sheet Presentation")
        app.cells["demo.sheetPresentation.title"].tap()
        let options = app.buttons["sheet.options"]
        for title in ["Allow background through Medium", "Scroll to expand", "Add 1/3 detent"] {
            options.tap()
            app.buttons[title].tap()
        }
        let background = app.buttons["sheet.background"]
        let list = app.tables["sheet.list"]
        for (index, engine) in ["UIKit", "QuickLayoutKit"].enumerated() {
            app.segmentedControls["sheet.engine"].buttons[engine].tap()
            app.buttons["sheet.open"].tap()
            let medium = list.frame
            background.tap()
            XCTAssertTrue(background.label.contains(String(index + 1)))
            list.swipeUp()
            XCTAssertFalse(app.cells["sheet.row.0"].isHittable)
            XCTAssertEqual(list.frame.minY, medium.minY, accuracy: 2)
            app.buttons["sheet.third"].tap()
            XCTAssertGreaterThan(list.frame.minY, medium.minY + 50)
            app.buttons["sheet.large"].tap()
            XCTAssertLessThan(list.frame.minY, medium.minY - 100)
            app.buttons["sheet.close"].tap()
        }
        options.tap()
        app.buttons["Scroll to expand"].tap()
        for engine in ["UIKit", "QuickLayoutKit"] {
            app.segmentedControls["sheet.engine"].buttons[engine].tap()
            app.buttons["sheet.open"].tap()
            let start = list.frame.minY
            list.swipeUp()
            XCTAssertLessThan(list.frame.minY, start - 100)
            XCTAssertTrue(app.buttons["sheet.large"].isSelected)
            app.buttons["sheet.close"].tap()
        }
    }

}
