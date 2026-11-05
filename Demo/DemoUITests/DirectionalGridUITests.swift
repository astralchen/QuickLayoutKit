import XCTest

final class DirectionalGridUITests: XCTestCase {
    @MainActor
    func testViewportGuideFollowsAxisAndAlignment() {
        let app = openGridPage()
        let axis = app.segmentedControls["directionalGrid.axis"]
        let alignment = app.segmentedControls["directionalGrid.alignment"]
        let direction = app.segmentedControls["directionalGrid.direction"]
        let slider = app.sliders["directionalGrid.width"]
        let preview = app.descendants(matching: .any)["directionalGrid.preview"]
        let viewport = app.scrollViews["directionalGrid.viewport"]
        let title = app.staticTexts["directionalGrid.availableSpace"]
        let hint = app.staticTexts["directionalGrid.availableSpaceHint"]
        slider.adjust(toNormalizedSliderPosition: 0)
        // 再切回 HGrid，覆盖切换布局后遗留宽度、高度或对齐状态的回归。
        for (step, name) in ["HGrid", "VGrid", "HGrid"].enumerated() {
            axis.buttons[name].tap()
            let horizontal = name == "HGrid"
            let labels = horizontal ? ["top", "center", "bottom"] : ["leading", "center", "trailing"]
            XCTAssertTrue(title.label.contains(horizontal ? "Available height" : "Available width"))
            XCTAssertTrue(hint.label.contains(horizontal ? "height" : "width"))
            for rtl in [false, true] {
                direction.buttons[rtl ? "RTL" : "LTR"].tap()
                for (index, label) in labels.enumerated() {
                    alignment.buttons[label].tap()
                    waitFor {
                        let container = preview.frame.insetBy(dx: 12, dy: 12)
                        let physicalIndex = !horizontal && rtl ? 2 - index : index
                        let expected = horizontal
                            ? CGRect(x: container.minX,
                                     y: container.minY + container.height * 0.55 * CGFloat(physicalIndex) / 2,
                                     width: container.width, height: container.height * 0.45)
                            : CGRect(x: container.minX + container.width * 0.55 * CGFloat(physicalIndex) / 2,
                                     y: container.minY,
                                     width: container.width * 0.45, height: container.height)
                        let actual = viewport.frame
                        return abs(actual.minX - expected.minX) < 2
                            && abs(actual.minY - expected.minY) < 2
                            && abs(actual.width - expected.width) < 2
                            && abs(actual.height - expected.height) < 2
                    }
                    let length = horizontal ? viewport.frame.height : viewport.frame.width
                    XCTAssertTrue(title.label.contains(String(format: "%.0f pt", length)))
                    XCTAssertTrue(title.label.contains("45%"))
                    capture("Viewport-\(step)-\(name)-\(rtl ? "RTL" : "LTR")-\(label)")
                }
            }
        }
    }

    @MainActor
    func testGridPageSwitchesAxisSizingAndDirection() {
        let app = openGridPage()
        let axis = app.segmentedControls["directionalGrid.axis"]
        let first = app.staticTexts["directionalGrid.card.0"]
        let second = app.staticTexts["directionalGrid.card.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(second.frame.minX, first.frame.minX)
        app.segmentedControls["directionalGrid.direction"].buttons["RTL"].tap()
        waitFor { second.frame.minX < first.frame.minX }
        app.sliders["directionalGrid.width"].adjust(toNormalizedSliderPosition: 0)
        capture("VGrid-RTL-ReducedWidth")
        app.sliders["directionalGrid.width"].adjust(toNormalizedSliderPosition: 1)
        capture("VGrid-RTL")
        axis.buttons["HGrid"].tap()
        waitFor { second.frame.minY > first.frame.minY }
        for rule in ["fixed", "flexible", "mixed", "adaptive"] {
            app.segmentedControls["directionalGrid.sizing"].buttons[rule].tap()
            XCTAssertGreaterThan(first.frame.width, 0)
            XCTAssertGreaterThan(first.frame.height, 0)
        }
        capture("HGrid-RTL")
    }

    @MainActor
    func testGridContentStaysBesideVisibleSidebar() throws {
        let app = openGridPage()
        let route = app.cells["demo.directionalGrid.title"]
        guard route.isHittable else {
            throw XCTSkip("此回归需要展开且可见的目录侧栏；单列导航不计为分栏通过")
        }
        let sidebarEdge = route.frame.maxX
        let axis = app.segmentedControls["directionalGrid.axis"]
        let slider = app.sliders["directionalGrid.width"]
        let preview = app.descendants(matching: .any)["directionalGrid.preview"]
        XCTAssertTrue(preview.exists)
        for axisName in ["VGrid", "HGrid"] {
            axis.buttons[axisName].tap()
            for direction in ["LTR", "RTL"] {
                app.segmentedControls["directionalGrid.direction"].buttons[direction].tap()
                for element in [axis, slider, preview] {
                    XCTAssertGreaterThanOrEqual(element.frame.minX, sidebarEdge,
                                                "\(axisName) \(direction) must clear the visible sidebar")
                    XCTAssertLessThanOrEqual(element.frame.maxX, app.windows.firstMatch.frame.maxX)
                }
                XCTAssertTrue(axis.buttons["VGrid"].isHittable)
                XCTAssertTrue(axis.buttons["HGrid"].isHittable)
                capture("Split-\(axisName)-\(direction)")
            }
        }
    }

    @MainActor private func openGridPage() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let showSidebar = app.buttons["Show Sidebar"]
        if showSidebar.waitForExistence(timeout: 2), showSidebar.isHittable {
            showSidebar.tap()
        }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("HGrid")
        let route = app.cells["demo.directionalGrid.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let axis = app.segmentedControls["directionalGrid.axis"]
        XCTAssertTrue(axis.waitForExistence(timeout: 5))
        return app
    }

    private func waitFor(_ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
