import XCTest

final class TrailGuideUITests: XCTestCase {
    @MainActor func testRouteToPlaceAndItineraryRoundTrip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-quicklayoutkit.demo.locale.identifier", "zh-Hans"]
        app.launch()
        let catalog = app.collectionViews.firstMatch
        let guide = app.cells["trail.title"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if guide.exists && guide.isHittable { break }
            catalog.swipeUp()
        }
        XCTAssertTrue(guide.isHittable)
        guide.tap()

        XCTAssertTrue(app.cells["trail.route.mountains"].waitForExistence(timeout: 5))
        let coverTitle = app.staticTexts["山野里的周末"]
        XCTAssertTrue(coverTitle.exists)
        capture(app, "TrailGuide-Routes")
        app.cells["trail.route.mountains"].tap()
        let ridge = app.cells["trail.place.ridge"]
        ridge.tap()
        let toggle = app.buttons["trail.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        capture(app, "TrailGuide-Place")
        let wasSaved = toggle.label == "从行程中移除"
        if !wasSaved { toggle.tap() }
        XCTAssertEqual(toggle.label, "从行程中移除")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ridge.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let trip = app.buttons["tab.2"]
        trip.tap()
        XCTAssertTrue(ridge.waitForExistence(timeout: 5))
        ridge.tap()
        toggle.tap()
        XCTAssertEqual(toggle.label, "加入我的行程")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ridge.waitForNonExistence(timeout: 5))
        let browse = app.cells["trail.browse"]
        if browse.isHittable {
            browse.tap()
        } else {
            app.buttons["tab.1"].tap()
        }

        let places = app.buttons["tab.1"]
        XCTAssertTrue(ridge.waitForExistence(timeout: 5))
        let expandedY = places.frame.minY
        let table = ridge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        table.press(forDuration: 0.05, thenDragTo: table.withOffset(CGVector(dx: 0, dy: -200)))
        XCTAssertLessThan(places.frame.minY, expandedY)
        XCTAssertFalse(coverTitle.exists)
        capture(app, "TrailGuide-Pinned")
        app.swipeRight()
        XCTAssertTrue(app.cells["trail.route.mountains"].waitForExistence(timeout: 5))
        XCTAssertFalse(coverTitle.exists)
        app.swipeDown()
        XCTAssertTrue(coverTitle.waitForExistence(timeout: 5))

        app.cells["trail.route.mountains"].tap()
        ridge.tap()
        if wasSaved { toggle.tap() }
        app.buttons["trail.preview"].tap()
        let photoCanvas = app.otherElements["QLMarkupImageItemViewControllerMarkupImageViewAccessibilityIdentifier"]
        XCTAssertTrue(photoCanvas.waitForExistence(timeout: 20))
        let closePreview = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        if !closePreview.isHittable { photoCanvas.tap() }
        XCTAssertTrue(closePreview.waitForExistence(timeout: 10))
        closePreview.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
