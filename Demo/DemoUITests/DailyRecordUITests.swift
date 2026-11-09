import XCTest

final class DailyRecordUITests: XCTestCase {
    @MainActor func testRecordSheetDismissalAndEmptyDay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Daily Records")
        app.cells["demo.dailyRecord.title"].tap()
        let open = app.buttons["dailyRecord.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let date = app.staticTexts["dailyRecord.date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.component(.day, from: Date())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMMdEEEE")
        XCTAssertEqual(date.label, formatter.string(from: Date()))
        XCTAssertTrue(app.otherElements["dailyRecord.session"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "dailyRecord.duration").allElementsBoundByIndex.last?.label, "32 min 24 sec")
        capture(app, "Daily record at medium detent")
        app.buttons["dailyRecord.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let emptyDay = app.buttons["dailyRecord.day.\(today == 1 ? 2 : 1)"]
        if !emptyDay.isHittable { app.swipeUp() }
        emptyDay.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No records for this day"].exists)
        XCTAssertFalse(app.otherElements["dailyRecord.session"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "dailyRecord.duration").allElementsBoundByIndex.last?.label, "0 min")
        capture(app, "Empty daily record")
        app.buttons["dailyRecord.close"].tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
