import XCTest

final class GeometryDemoUITests: XCTestCase {
    @MainActor
    func testGeometryScenariosAndDirection() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { search.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Geometry")
        let route = app.cells["demo.geometry.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let scenario = app.buttons["geometry.scenario"]
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["geometry.metrics"].exists)
        assertContentFits(app, beside: route)
        app.sliders["geometry.width"].adjust(toNormalizedSliderPosition: 1)
        assertContentFits(app, beside: route)
        capture("Geometry-portrait")
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
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        assertContentFits(app, beside: route)
        capture("Geometry-landscape")
    }

    @MainActor private func assertContentFits(_ app: XCUIApplication, beside route: XCUIElement,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let scenario = app.buttons["geometry.scenario"]
        let canvas = app.descendants(matching: .any).matching(identifier: "geometry.canvas").firstMatch
        let minimumX = route.isHittable ? route.frame.maxX : app.frame.minX
        let maximumX = app.frame.maxX
        let elements: [(String, XCUIElement)] = [
            ("scenario", scenario), ("options", app.buttons["geometry.options"]),
            ("direction", app.buttons["geometry.direction"]), ("width", app.sliders["geometry.width"]),
            ("margin", app.sliders["geometry.margin"]), ("canvas", canvas),
            ("metrics", app.staticTexts["geometry.metrics"]), ("code", app.staticTexts["geometry.code"])
        ]
        for (name, element) in elements {
            XCTAssertTrue(element.exists, file: file, line: line)
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, minimumX, "\(name) overlaps the sidebar", file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, maximumX, "\(name) exceeds the window", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(canvas.frame.width, scenario.frame.width + 1, file: file, line: line)
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
