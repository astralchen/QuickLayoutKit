import ImageIO
import XCTest

final class GeometryUITests: XCTestCase {
    /// 对照同一详情列内的两种实现，拉满滑块后实际拖至两端，分别检查视口与内容。
    @MainActor func testNestedCanvasViewportAndDragMatchSwiftUI() {
        continueAfterFailure = false
        var fullWidthReference = CGRect.zero
        for reference in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
            if reference { app.launchArguments.append("-geometry-scroll-swiftui-reference") }
            app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft
            let window = app.windows.firstMatch
            let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                window.frame.width > window.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [wide], timeout: 60), .completed)
            let sidebar = app.buttons["Show Sidebar"]
            if sidebar.exists && sidebar.isHittable { sidebar.tap() }
            let entry = app.cells["demo.geometry.title"]
            let menu = app.collectionViews.firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            for _ in 0..<5 where !entry.isHittable { menu.swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.tap()
            let width = app.sliders["geometry.width"]
            XCTAssertTrue(width.waitForExistence(timeout: 10))
            app.sliders["geometry.margin"].adjust(toNormalizedSliderPosition: 0.9)
            let canvas = app.descendants(matching: .any)["geometry.canvas"]
            let inner = app.scrollViews["geometry.horizontal"]
            let sample = app.descendants(matching: .any)["geometry.sample"]
            for fraction in [0.8, 1.0] {
                width.adjust(toNormalizedSliderPosition: fraction)
                XCTAssertTrue(canvas.exists && inner.exists && sample.exists, app.debugDescription)
                let bounds = canvas.frame
                let viewport = inner.frame
                print("GeometryDrag reference=\(reference) slider=\(fraction) window=\(window.frame) canvas=\(bounds) viewport=\(viewport) sample=\(sample.frame)")
                XCTAssertEqual(bounds.minX, viewport.minX, accuracy: 1)
                XCTAssertEqual(bounds.maxX, viewport.maxX, accuracy: 1)
                XCTAssertEqual(bounds.midY, viewport.midY, accuracy: 1)
                XCTAssertEqual(viewport.height, 200, accuracy: 1)
                // 中间位置由真实触点决定，两套滑块的取值可能略有不同；终点才是相同输入。
                if fraction == 1 {
                    if reference {
                        fullWidthReference = bounds
                    } else {
                        XCTAssertEqual(bounds.minX, fullWidthReference.minX, accuracy: 1)
                        XCTAssertEqual(bounds.maxX, fullWidthReference.maxX, accuracy: 1)
                    }
                }
            }
            let before = sample.frame
            let left = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
            let right = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            right.press(forDuration: 0.05, thenDragTo: left)
            let end = sample.frame
            print("GeometryEnd reference=\(reference) sample=\(end) canvas=\(canvas.frame)")
            XCTAssertLessThan(end.minX, before.minX - 30)
            XCTAssertEqual(canvas.frame.maxX - end.maxX, before.minX - canvas.frame.minX, accuracy: 1)
            left.press(forDuration: 0.05, thenDragTo: right)
            XCTAssertEqual(sample.frame.minX, before.minX, accuracy: 1)
            // Duo 的默认截图可能来自熄灭的外屏，保留各屏原图核对实际内屏。
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let attachment = XCTAttachment(screenshot: screen.screenshot())
                attachment.name = "geometry-\(reference ? "swiftui" : "kit")-returned-\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.terminate()
        }
    }

    /// 用阿拉伯语运行真实页面；满宽后不再调整滑块，连续旋转并核对 RTL 的两个端点。
    @MainActor func testRTLFullWidthCanvasAcrossRotationMatchesSwiftUI() throws {
        continueAfterFailure = false
        var referenceFrames: [UIDeviceOrientation: CGRect] = [:]
        for reference in [true, false] {
            let app = openFullWidthRTLCanvas(reference: reference)
            let window = app.windows.firstMatch
            let canvas = app.descendants(matching: .any)["geometry.canvas"]
            let inner = app.scrollViews["geometry.horizontal"]
            let sample = app.descendants(matching: .any)["geometry.sample"]
            for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
                print("GeometryRTL rotating reference=\(reference) orientation=\(orientation.rawValue)")
                XCUIDevice.shared.orientation = orientation
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let frame = window.frame
                    return (orientation == .portrait ? frame.height > frame.width : frame.width > frame.height)
                        && inner.exists && canvas.exists && sample.exists
                        && self.matchesDuoScreenOrientation(orientation)
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 60), .completed)
                let bounds = canvas.frame, viewport = inner.frame, before = sample.frame
                print("GeometryRTL reference=\(reference) orientation=\(orientation.rawValue) window=\(window.frame) canvas=\(bounds) viewport=\(viewport) start=\(before)")
                XCTAssertEqual(bounds.minX, viewport.minX, accuracy: 1)
                XCTAssertEqual(bounds.maxX, viewport.maxX, accuracy: 1)
                XCTAssertEqual(bounds.height, 260, accuracy: 1)
                XCTAssertEqual(bounds.midY, viewport.midY, accuracy: 1)
                XCTAssertEqual(viewport.height, 200, accuracy: 1)
                XCTAssertEqual(before.width, bounds.width * 1.6, accuracy: 1)
                XCTAssertEqual(bounds.maxX - before.maxX, 16, accuracy: 1)
                if reference {
                    referenceFrames[orientation] = bounds
                } else {
                    let expected = try XCTUnwrap(referenceFrames[orientation])
                    XCTAssertEqual(bounds.minX, expected.minX, accuracy: 1)
                    XCTAssertEqual(bounds.width, expected.width, accuracy: 1)
                }
                let visible = viewport.intersection(window.frame)
                let origin = window.coordinate(withNormalizedOffset: .zero)
                let left = origin.withOffset(CGVector(dx: visible.minX + visible.width * 0.14, dy: visible.midY))
                let right = origin.withOffset(CGVector(dx: visible.maxX - visible.width * 0.14, dy: visible.midY))
                left.press(forDuration: 0.05, thenDragTo: right)
                let end = sample.frame
                XCTAssertEqual(end.minX - bounds.minX, 16, accuracy: 1)
                XCTAssertGreaterThan(end.minX - before.minX, 30)
                right.press(forDuration: 0.05, thenDragTo: left)
                let returned = sample.frame
                print("GeometryRTL endpoints end=\(end) returned=\(returned)")
                XCTAssertEqual(returned.maxX, before.maxX, accuracy: 1)
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let attachment = XCTAttachment(screenshot: screen.screenshot())
                    attachment.name = "geometry-rtl-\(reference ? "swiftui" : "kit")-\(orientation.rawValue)-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            // 页面内的方向按钮只切换画布；在同一竖屏验证两次切换后分别停在逻辑起点。
            if !reference {
                let direction = app.buttons["geometry.direction"]
                direction.tap()
                XCTAssertEqual(direction.label, "LTR")
                XCTAssertEqual(sample.frame.minX - canvas.frame.minX, 16, accuracy: 1)
                direction.tap()
                XCTAssertEqual(direction.label, "RTL")
                XCTAssertEqual(canvas.frame.maxX - sample.frame.maxX, 16, accuracy: 1)
            }
            app.terminate()
        }
    }

    /// 从竖屏中途松手，连续旋转；两页分别以自己的真实落点为基准比较位移。
    @MainActor func testRTLCanvasMiddlePositionAcrossRotationMatchesSwiftUI() throws {
        continueAfterFailure = false
        var referencePositions: [UIDeviceOrientation: (distance: CGFloat, range: CGFloat, initial: CGFloat)] = [:]
        for reference in [true, false] {
            let app = openFullWidthRTLCanvas(reference: reference)
            let viewport = app.scrollViews["geometry.horizontal"]
            let sample = app.descendants(matching: .any)["geometry.sample"]
            var initialDistance: CGFloat = 0
            for (step, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight, .portrait].enumerated() {
                print("MiddleRotate reference=\(reference) step=\(step) orientation=\(orientation.rawValue)")
                XCUIDevice.shared.orientation = orientation
                let window = app.windows.firstMatch
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    self.matchesDuoScreenOrientation(orientation)
                        && ((window.frame.width > window.frame.height) == orientation.isLandscape)
                        && viewport.exists && sample.exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 60), .completed)
                if step == 0 {
                    let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
                    let halfRange = (sample.frame.width + 32 - viewport.frame.width) / 2
                    let end = start.withOffset(CGVector(dx: halfRange, dy: 0))
                    start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 180, thenHoldForDuration: 0.5)
                }
                // 等两次采样一致才记录，避免将惯性或旋转动画的中间帧算作最终位置。
                var lastFrame = CGRect.null
                let resting = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let frame = sample.frame
                    defer { lastFrame = frame }
                    return frame == lastFrame
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [resting], timeout: 8), .completed)
                let frame = sample.frame, bounds = viewport.frame
                let range = frame.width + 32 - bounds.width
                let distance = frame.maxX + 16 - bounds.maxX
                print("MiddlePosition reference=\(reference) step=\(step) viewport=\(bounds) sample=\(frame) distance=\(distance) range=\(range)")
                XCTAssertEqual(frame.width, bounds.width * 1.6, accuracy: 1)
                if step == 0 {
                    XCTAssertEqual(distance / range, 0.5, accuracy: 0.10)
                    initialDistance = distance
                } else if reference {
                    referencePositions[orientation] = (distance, range, initialDistance)
                } else {
                    let expected = try XCTUnwrap(referencePositions[orientation])
                    XCTAssertEqual(range, expected.range, accuracy: 1)
                    // 原生分栏重排也可能停到某一端。端点比较实际距离，中途比较相对松手点的位移。
                    let atEdge = min(expected.distance, expected.range - expected.distance) < 1
                    let target = atEdge ? expected.distance : expected.distance - expected.initial + initialDistance
                    XCTAssertEqual(distance, target, accuracy: 1)
                }
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let attachment = XCTAttachment(screenshot: screen.screenshot())
                    attachment.name = "rtl-middle-\(reference ? "swiftui" : "kit")-\(step)-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            app.terminate()
        }
    }

    @MainActor private func openFullWidthRTLCanvas(reference: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-quicklayoutkit.demo.locale.identifier", "ar"]
        if reference { app.launchArguments.append("-geometry-scroll-swiftui-reference") }
        // 两页从相同的展开姿态启动，避免取到竖屏启动时尚未展开的目录。
        XCUIDevice.shared.orientation = .landscapeLeft
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.matchesDuoScreenOrientation(.landscapeLeft)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed)
        app.launch()
        let entry = app.cells["demo.geometry.title"]
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("مراقبة الأبعاد")
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let width = app.sliders["geometry.width"]
        XCTAssertTrue(width.waitForExistence(timeout: 10))
        if !reference { XCTAssertEqual(app.buttons["geometry.direction"].label, "RTL") }
        // RTL 下最大值位于物理左端，从默认值 0.8 的滑块手柄开始实际拖动。
        let thumb = width.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.5))
        thumb.press(forDuration: 0.1, thenDragTo: width.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)))
        return app
    }

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

extension XCTestCase {
    /// Duo 可以保持旧的内屏朝向。用截图的物理旋转信息区分两个等宽的横屏。
    @MainActor func matchesDuoScreenOrientation(_ orientation: UIDeviceOrientation) -> Bool {
        let screens = XCUIScreen.screens
        guard screens.count > 1 else { return true }
        let image = screens[1].screenshot().pngRepresentation
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        let actual = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let expected: CGImagePropertyOrientation = orientation == .portrait ? .up
            : orientation == .landscapeLeft ? .left : .right
        return actual == expected.rawValue
    }
}
