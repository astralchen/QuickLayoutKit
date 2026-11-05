import XCTest

final class GeometryUITests: XCTestCase {
    @MainActor
    func testAdaptiveGridChangesColumnsAndDirection() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { search.tap() }
        search.typeText("Geometry")
        let route = app.cells["demo.geometry.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let scenario = app.buttons["geometry.scenario"]
        XCTAssertTrue(scenario.waitForExistence(timeout: 5))
        scenario.tap()
        app.buttons["Adaptive Grid"].tap()
        let width = app.sliders["geometry.width"]
        width.adjust(toNormalizedSliderPosition: 1)
        assertAdaptiveGrid(app, rtl: false, multipleColumns: true)
        width.adjust(toNormalizedSliderPosition: 0)
        assertAdaptiveGrid(app, rtl: false, multipleColumns: false)
        width.adjust(toNormalizedSliderPosition: 1)
        app.buttons["geometry.direction"].tap()
        assertAdaptiveGrid(app, rtl: true, multipleColumns: true)
        capture("AdaptiveGrid-RTL")
        // 切出再切回后卡片应重新挂载，保持当前宽度与方向。
        scenario.tap()
        app.buttons["GeometryReader"].tap()
        assertReaderProportions(app, rtl: true)
        scenario.tap()
        app.buttons["Adaptive Grid"].tap()
        assertAdaptiveGrid(app, rtl: true, multipleColumns: true)
    }

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
        scenario.tap()
        app.buttons["GeometryReader"].tap()
        assertReaderProportions(app, rtl: false)
        app.sliders["geometry.width"].adjust(toNormalizedSliderPosition: 0.3)
        assertReaderProportions(app, rtl: false)
        app.buttons["geometry.direction"].tap()
        assertReaderProportions(app, rtl: true)
        capture("GeometryReader-RTL")
        app.buttons["geometry.direction"].tap()
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

    @MainActor private func assertAdaptiveGrid(_ app: XCUIApplication, rtl: Bool, multipleColumns: Bool,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let grid = app.descendants(matching: .any).matching(identifier: "geometry.grid").firstMatch
        let cards = (0..<6).map { app.staticTexts["geometry.grid.card.\($0)"] }
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard grid.exists, cards.allSatisfy(\.exists) else { return false }
            let bounds = grid.frame
            let available = bounds.width - 32
            let columns = min(4, max(1, Int((available + 12) / 116)))
            guard (columns > 1) == multipleColumns else { return false }
            let rows = (6 + columns - 1) / columns
            let cellWidth = (available - CGFloat(columns - 1) * 12) / CGFloat(columns)
            let cellHeight = (bounds.height - 32 - CGFloat(rows - 1) * 12) / CGFloat(rows)
            return cards.enumerated().allSatisfy { index, card in
                let frame = card.frame
                let column = rtl ? columns - 1 - index % columns : index % columns
                return abs(frame.width - cellWidth) < 1 && abs(frame.height - cellHeight) < 1 &&
                    abs(frame.minX - (bounds.minX + 16 + CGFloat(column) * (cellWidth + 12))) < 1 &&
                    abs(frame.minY - (bounds.minY + 16 + CGFloat(index / columns) * (cellHeight + 12))) < 1
            }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor private func assertReaderProportions(_ app: XCUIApplication, rtl: Bool,
                                                   file: StaticString = #filePath, line: UInt = #line) {
        let canvas = app.descendants(matching: .any).matching(identifier: "geometry.canvas").firstMatch
        let child = app.descendants(matching: .any).matching(identifier: "geometry.reader.sample").firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard child.exists else { return false }
            let parent = canvas.frame, frame = child.frame
            return abs(frame.width - parent.width * 0.5) < 1 &&
                abs(frame.height - parent.height * 0.6) < 1 &&
                abs(frame.minY - parent.minY) < 1 &&
                abs((rtl ? frame.maxX - parent.maxX : frame.minX - parent.minX)) < 1
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, file: file, line: line)
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
