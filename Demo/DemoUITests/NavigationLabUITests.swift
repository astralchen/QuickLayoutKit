import XCTest

final class NavigationLabUITests: XCTestCase {
    @MainActor private func openGuide(locale: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()

        let route = app.cells["demo.navigationLab.title"]
        let catalog = app.collectionViews.firstMatch
        let sidebar = app.buttons.matching(NSPredicate(format: "label IN %@", ["Show Sidebar", "显示边栏", "显示侧边栏"])).firstMatch
        if !catalog.exists && sidebar.isHittable { sidebar.tap() }
        XCTAssertTrue(catalog.waitForExistence(timeout: 8))
        for _ in 0..<10 where !route.isHittable { catalog.swipeUp() }
        XCTAssertTrue(route.isHittable)
        route.tap()
        return app
    }

    @MainActor func testGuideCoverAutoAdvancesOnlyWhileIdle() {
        let app = openGuide(locale: "en")
        let cover = app.scrollViews["navLab.coverPager"]
        let title = app.staticTexts["navLab.featured"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.press(forDuration: 6)
        XCTAssertEqual(title.label, "Last light")

        func waitForTitle(_ label: String) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        }
        waitForTitle("Lakeside cabin")
        XCTAssertTrue(app.buttons["navLab.previous"].isEnabled)
        let center = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: -35, dy: 0)),
                     withVelocity: .slow, thenHoldForDuration: 6)
        XCTAssertEqual(title.label, "Lakeside cabin")
        let prematureAdvance = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Lakeside cabin'"), object: title)
        prematureAdvance.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureAdvance], timeout: 2), .completed)
        let next = app.buttons["navLab.next"]
        for _ in 0..<4 { next.tap() }
        XCTAssertFalse(next.isEnabled)
        waitForTitle("Last light")
        XCTAssertFalse(app.buttons["navLab.previous"].isEnabled)

        app.segmentedControls["navLab.toolbarPosition"].buttons["System bottom bar"].tap()
        XCTAssertTrue(app.buttons["navLab.closePreview"].waitForExistence(timeout: 5))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Last light'"), object: title)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 6), .completed)
    }

    @MainActor func testGuideCoverSwipesAndToolbarShareSelection() throws {
        let app = openGuide(locale: "en")
        let cover = app.scrollViews["navLab.coverPager"]
        let title = app.staticTexts["navLab.featured"]
        let previous = app.buttons["navLab.previous"]
        let next = app.buttons["navLab.next"]
        let bookmark = app.buttons["navLab.bookmark"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertFalse(previous.isEnabled)
        let firstImage = try centerPixels(of: cover)
        cover.swipeLeft()
        XCTAssertEqual(title.label, "Lakeside cabin")
        XCTAssertTrue(previous.isEnabled)
        let secondImage = try centerPixels(of: cover)
        XCTAssertNotEqual(firstImage, secondImage)
        bookmark.tap()
        previous.tap()
        XCTAssertFalse(previous.isEnabled)
        XCTAssertEqual(try centerPixels(of: cover), firstImage)
        next.tap()
        XCTAssertEqual(try centerPixels(of: cover), secondImage)
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        cover.swipeRight()
        XCTAssertEqual(title.label, "Last light")
        XCTAssertFalse(previous.isEnabled)

        let controls = app.segmentedControls["navLab.toolbarPosition"]
        let originalY = controls.frame.minY
        cover.swipeUp()
        XCTAssertLessThan(controls.frame.minY, originalY)
        XCTAssertEqual(title.label, "Last light")
    }

    @MainActor func testMovingActionsToTheSystemToolbar() throws {
        let app = openGuide(locale: "en")
        let position = app.segmentedControls["navLab.toolbarPosition"]
        let next = app.buttons["navLab.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let coverButtonY = next.frame.midY
        position.buttons["System bottom bar"].tap()
        let close = app.buttons["navLab.closePreview"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThan(next.frame.midY, app.windows.firstMatch.frame.midY)
        XCTAssertLessThanOrEqual(app.staticTexts["navLab.featured"].frame.maxY, next.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "NavigationController-BottomToolbar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let pager = app.scrollViews["navLab.photoPager"]
        let title = app.staticTexts["navLab.featured"]
        let previous = app.buttons["navLab.previous"]
        let bookmark = app.buttons["navLab.bookmark"]
        XCTAssertTrue(pager.isHittable)
        let initialButtonFrame = next.frame
        let centered = try centerPixels(of: pager)
        pager.swipeRight()
        XCTAssertEqual(title.label, "Last light")
        XCTAssertFalse(previous.isEnabled)
        pager.swipeLeft()
        XCTAssertEqual(title.label, "Lakeside cabin")
        XCTAssertTrue(previous.isEnabled)
        XCTAssertEqual(next.frame, initialButtonFrame)
        bookmark.tap()
        pager.swipeRight()
        XCTAssertEqual(title.label, "Last light")
        XCTAssertEqual(try centerPixels(of: pager), centered)
        next.tap()
        XCTAssertEqual(title.label, "Lakeside cabin")
        XCTAssertEqual(bookmark.label, "Remove bookmark")
        pager.swipeUp()
        XCTAssertEqual(title.label, "Lakeside cabin")
        pager.swipeLeft()
        let woodlandTitle = title.label
        XCTAssertNotEqual(woodlandTitle, "Lakeside cabin")
        if pager.frame.width / pager.frame.height > 1000.0 / 1651.0 {
            let before = try centerPixels(of: pager)
            pager.swipeUp()
            XCTAssertEqual(title.label, woodlandTitle)
            XCTAssertNotEqual(try centerPixels(of: pager), before)
        }
        pager.swipeRight()
        XCTAssertEqual(title.label, "Lakeside cabin")
        close.tap()
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["navLab.featured"].label, "Lakeside cabin")
        XCTAssertTrue(next.isHittable)
        XCTAssertEqual(next.frame.midY, coverButtonY, accuracy: 6)
    }

    @MainActor func testFullScreenPhotoZoomAndPaging() throws {
        let app = openGuide(locale: "en")
        app.segmentedControls["navLab.toolbarPosition"].buttons["System bottom bar"].tap()
        let pager = app.scrollViews["navLab.photoPager"]
        let title = app.staticTexts["navLab.featured"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let original = try centerPixels(of: pager)
        pager.pinch(withScale: 2, velocity: 1)
        let enlarged = try centerPixels(of: pager)
        XCTAssertNotEqual(enlarged, original)
        pager.swipeLeft()
        XCTAssertEqual(title.label, "Last light")
        let panned = try centerPixels(of: pager)
        XCTAssertNotEqual(panned, enlarged)
        app.buttons["navLab.bookmark"].tap()
        XCTAssertEqual(try centerPixels(of: pager), panned)

        for _ in 0..<8 where title.label == "Last light" { pager.swipeLeft() }
        XCTAssertEqual(title.label, "Lakeside cabin")
        pager.swipeRight()
        XCTAssertEqual(title.label, "Last light")
        XCTAssertEqual(try centerPixels(of: pager), original)
        pager.doubleTap()
        let doubleTapped = try centerPixels(of: pager)
        XCTAssertNotEqual(doubleTapped, original)
        // Keep both fingers on the photo, above the floating toolbar’s hit area.
        title.pinch(withScale: 0.25, velocity: -1)
        XCTAssertNotEqual(try centerPixels(of: pager), doubleTapped)
        // The short caption on a compact phone limits the travel of each pinch.
        title.pinch(withScale: 0.25, velocity: -1)
        pager.swipeLeft()
        XCTAssertEqual(title.label, "Lakeside cabin")
    }

    @MainActor private func centerPixels(of photo: XCUIElement) throws -> Data {
        let image = try XCTUnwrap(photo.screenshot().image.cgImage)
        let patch = CGRect(x: image.width / 2 - 32, y: image.height / 2 - 32, width: 64, height: 64)
        let cropped = try XCTUnwrap(image.cropping(to: patch))
        return try XCTUnwrap(UIImage(cgImage: cropped).pngData())
    }

    @MainActor func testChineseGuide() {
        let app = openGuide(locale: "zh-Hans")
        let featured = app.staticTexts["navLab.featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 5))
        XCTAssertEqual(featured.label, "日落之前")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TrailGuide-Chinese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["navLab.next"].tap()
        XCTAssertEqual(featured.label, "湖畔木屋")
    }

    @MainActor func testToolbarTitleModesAndRouteSearch() {
        let app = openGuide(locale: "en")
        let featured = app.staticTexts["navLab.featured"]
        XCTAssertTrue(featured.waitForExistence(timeout: 5))
        XCTAssertEqual(featured.label, "Last light")
        let previous = app.buttons["navLab.previous"]
        XCTAssertFalse(previous.isEnabled)
        app.buttons["navLab.next"].tap()
        XCTAssertEqual(featured.label, "Lakeside cabin")
        let bookmark = app.buttons["navLab.bookmark"]
        bookmark.tap()
        previous.tap()
        app.buttons["navLab.next"].tap()
        XCTAssertEqual(bookmark.label, "Remove bookmark")

        let modes = app.segmentedControls["navLab.titleMode"]
        modes.buttons["Large"].tap()
        XCTAssertTrue(modes.buttons["Large"].isSelected)
        if modes.buttons["Inline large"].exists {
            modes.buttons["Inline large"].tap()
            XCTAssertTrue(modes.buttons["Inline large"].isSelected)
        }
        modes.buttons["Inline"].tap()
        app.segmentedControls["navLab.searchMode"].buttons["Always visible"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("green")
        let forest = app.buttons["navLab.route.forest"]
        XCTAssertTrue(forest.isHittable)
        XCTAssertFalse(app.buttons["navLab.route.lake"].exists)
        forest.tap()
        XCTAssertTrue(featured.waitForExistence(timeout: 5))
        XCTAssertEqual(featured.label, "Into the green")
    }
}
