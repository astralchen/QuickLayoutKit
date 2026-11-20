import XCTest

@MainActor
final class SheetContainerUITests: XCTestCase {
    private func openExample() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sheet-geometry", "-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.exists && sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Sheet Presentation")
        app.cells["demo.sheetPresentation.title"].tap()
        let hide = app.buttons["Hide Sidebar"]
        if hide.exists && hide.isHittable { hide.tap() }
        return app
    }

    func testPhoneRotatesIntoCompactHeight() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone") }
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        var reference: [CGRect] = []
        for engine in ["UIKit", "QuickLayoutKit"] {
            let app = openExample()
            let list = app.tables["sheet.list"]
            app.segmentedControls["sheet.engine"].buttons[engine].tap()
            for (index, mode) in ["edge", "pageWidth", "formWidth", "fullScreen"].enumerated() {
                if index > 0 {
                    app.buttons["sheet.options"].tap()
                    app.buttons[["", "Use preferred width at edge", "Use readable page size", "Attach in compact height"][index]].tap()
                }
                app.buttons["sheet.open"].tap()
                XCTAssertTrue(list.waitForExistence(timeout: 4))
                device.orientation = .landscapeLeft
                let window = app.windows.firstMatch
                XCTAssertTrue(waitUntil { window.frame.width > window.frame.height && list.frame.maxY <= window.frame.maxY + 1 })
                let rect = list.frame
                print("SHEET_COMPACT \(mode) \(engine) window=\(window.frame) list=\(rect) \(list.value ?? "")")
                if engine == "UIKit" { reference.append(rect) }
                else { compare(rect, reference[index]) }
                device.orientation = .portrait
                XCTAssertTrue(waitUntil { window.frame.height > window.frame.width })
                app.buttons["sheet.close"].tap()
                XCTAssertTrue(list.waitForNonExistence(timeout: 4))
            }
        }
    }

    private func waitUntil(_ predicate: @MainActor @escaping () -> Bool) -> Bool {
        let condition = NSPredicate { _, _ in MainActor.assumeIsolated { predicate() } }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: nil)], timeout: 8) == .completed
    }

    func testIPadWindowResize() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad") }
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .landscapeLeft
        let app = openExample()
        let window = app.windows.firstMatch
        let list = app.tables["sheet.list"]
        let initial = window.frame
        @MainActor func resize(by delta: CGVector) {
            let handle = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -9, dy: -10))
            handle.press(forDuration: 0.5, thenDragTo: handle.withOffset(delta))
        }
        @MainActor func capture(_ engine: String, _ state: String) -> CGRect {
            let frame = list.frame
            print("SHEET_WINDOW \(engine) \(state) window=\(window.frame) list=\(frame) \(list.value ?? "")")
            let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            evidence.name = "\(engine)-\(state)"
            evidence.lifetime = .keepAlways
            add(evidence)
            return frame.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
        @MainActor func present(_ engine: String) {
            app.segmentedControls["sheet.engine"].buttons[engine].tap()
            app.buttons["sheet.open"].tap()
            XCTAssertTrue(list.waitForExistence(timeout: 4))
        }
        @MainActor func close() {
            app.buttons["sheet.close"].tap()
            XCTAssertTrue(list.waitForNonExistence(timeout: 4))
        }
        present("UIKit")
        let before = capture("UIKit", "initial")
        close()
        present("QuickLayoutKit")
        let customBefore = capture("QuickLayoutKit", "initial")
        let delta = CGVector(dx: initial.width < 650 ? 150 : -180, dy: initial.height < 600 ? 110 : -145)
        resize(by: delta)
        XCTAssertTrue(waitUntil { abs(window.frame.width - initial.width) > 40 || abs(window.frame.height - initial.height) > 40 },
                      "拖动窗口把手后尺寸应变化 \(initial) / \(window.frame)")
        let resized = window.frame
        let customAfter = capture("QuickLayoutKit", "resized")
        close()
        present("UIKit")
        XCTAssertEqual(window.frame.size, resized.size)
        let after = capture("UIKit", "resized")
        resize(by: CGVector(dx: -delta.dx, dy: -delta.dy))
        close()
        compare(customBefore, before)
        compare(customAfter, after)
    }

    private func compare(_ actual: CGRect, _ expected: CGRect) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 2)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 2)
        XCTAssertEqual(actual.width, expected.width, accuracy: 2)
        XCTAssertEqual(actual.height, expected.height, accuracy: 2)
    }
}
