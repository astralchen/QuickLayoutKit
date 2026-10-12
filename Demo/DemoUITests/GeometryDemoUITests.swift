import XCTest

final class GeometryDemoUITests: XCTestCase {
    @MainActor
    func testGeometryScenariosAndDirection() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let route = app.cells["demo.geometry.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        for _ in 0..<5 where !route.isHittable { app.swipeUp() }
        route.tap()
        let scenario = app.buttons["geometry.scenario"]
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["geometry.metrics"].exists)
        for title in ["Anchors", "Container geometry", "Duo reserved regions"] {
            scenario.tap()
            app.buttons[title].tap()
            XCTAssertTrue(app.staticTexts["geometry.code"].exists)
        }
        app.buttons["geometry.direction"].tap()
        XCTAssertEqual(app.buttons["geometry.direction"].label, "RTL")
        app.sliders["geometry.width"].adjust(toNormalizedSliderPosition: 0.2)
        XCTAssertTrue(app.staticTexts["geometry.metrics"].label.contains("Callbacks"))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Geometry-Duo-regions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
