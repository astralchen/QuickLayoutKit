import XCTest

final class ArrangementExampleUITests: XCTestCase {
    @MainActor func testFloatingStyleAcrossLabAndWindowPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("ArrangementView")
        app.cells["demo.arrangement.title"].tap()
        let picker = app.buttons["arrangement.example"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Custom style"].tap()
        let primary = app.staticTexts["arrangement.primary"]
        let secondary = app.staticTexts["arrangement.secondary"]
        XCTAssertTrue(primary.label.contains("z = 1"))
        XCTAssertTrue(secondary.label.contains("z = 0"))
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(primary.label.contains("180 pt"))
        let engine = app.segmentedControls["arrangement.engine"]
        if #available(iOS 27.1, *) { engine.buttons["SwiftUI"].tap() }
        XCTAssertTrue(primary.label.contains("z = 1"))

        app.buttons["arrangement.openWindow"].tap()
        let close = app.buttons["arrangement.closeWindow"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        if #available(iOS 27.1, *) {
            XCTAssertTrue(engine.buttons["SwiftUI"].isSelected)
            engine.buttons["QuickLayoutKit"].tap()
        }
        XCTAssertTrue(primary.label.contains("z = 1"))
        XCTAssertFalse(primary.label.contains("180 pt"))
        close.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.label, "Custom style")
    }
}
