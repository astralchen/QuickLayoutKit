import XCTest

final class PopoverPresentationUITests: XCTestCase {
    @MainActor func testBothEnginesAnchorToTheCanvasTouch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.exists && sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Popover Presentation")
        app.cells["demo.popoverPresentation.title"].tap()
        let hide = app.buttons["Hide Sidebar"]
        if hide.exists && hide.isHittable { hide.tap() }
        let canvas = app.buttons["popover.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let engine = app.segmentedControls["popover.engine"]
        let close = app.buttons["popover.close"]
        var reference: [CGRect] = []
        for name in ["UIKit", "QuickLayoutKit"] {
            engine.buttons[name].tap()
            var positions: [CGRect] = []
            for fraction in [0.25, 0.75] {
                canvas.coordinate(withNormalizedOffset: .init(dx: fraction, dy: 0.50)).tap()
                XCTAssertTrue(close.waitForExistence(timeout: 4))
                positions.append(close.frame)
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 4))
            }
            // 窄窗口中两侧箭头可能相向，关闭按钮也会反向移动；两次触摸应产生不同位置。
            XCTAssertGreaterThan(hypot(positions[1].midX - positions[0].midX, positions[1].midY - positions[0].midY), 2, name)
            if name == "UIKit" { reference = positions }
            else {
                for (actual, expected) in zip(positions, reference) {
                    XCTAssertEqual(actual.midX, expected.midX, accuracy: 2)
                    XCTAssertEqual(actual.midY, expected.midY, accuracy: 2)
                }
            }
        }
    }
}
