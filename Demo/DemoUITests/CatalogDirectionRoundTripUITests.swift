import ImageIO
import Vision
import XCTest

@MainActor
final class CatalogDirectionRoundTripUITests: XCTestCase {
    private struct Measurement {
        let viewport: CGRect
        let left: CGFloat
        let right: CGFloat
        let indicatorOnLeft: Bool
    }

    func testRuntimeDirectionAndRotationMatchSwiftUI() throws {
        continueAfterFailure = false
        var control: [Measurement] = []
        for reference in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
            if reference { app.launchArguments.append("-catalog-scroll-swiftui-reference") }
            app.launch()
            try XCTSkipIf(XCUIScreen.screens.count < 2, "需要 Duo 展开内屏")
            var index = 0
            for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
                print("CatalogPose reference=\(reference) orientation=\(orientation.rawValue)")
                XCUIDevice.shared.orientation = orientation
                let window = app.windows.firstMatch
                waitUntil(timeout: 80) {
                    (window.frame.width > window.frame.height) == orientation.isLandscape
                        && self.matchesDuoScreenOrientation(orientation)
                }
                for (step, rtl) in [false, true, false].enumerated() {
                    let name = "\(reference ? "swiftui" : "kit")-\(orientation.rawValue)-\(step)"
                    if step > 0 { switchLanguage(in: app, rtl: rtl) }
                    let result = try measure(app, rtl: rtl, landscape: orientation.isLandscape, name: name)
                    if reference { control.append(result) }
                    else {
                        let expected = control[index]
                        XCTAssertEqual(result.viewport.minX, expected.viewport.minX, accuracy: 1, name)
                        XCTAssertEqual(result.viewport.width, expected.viewport.width, accuracy: 1, name)
                        XCTAssertEqual(result.left, expected.left, accuracy: 1, name)
                        XCTAssertEqual(result.right, expected.right, accuracy: 1, name)
                        XCTAssertEqual(result.indicatorOnLeft, expected.indicatorOnLeft, name)
                    }
                    index += 1
                }
            }
            app.terminate()
        }
    }

    private struct ReadingPosition {
        let id: String
        let offset: CGFloat
        let height: CGFloat
        let top: CGFloat
    }

    /// 三个姿态均通过真实手势把目录拖到中段，等滚动稳定，再走语言菜单。
    func testReferenceMiddleReadingPositionAcrossDirectionChanges() throws {
        try verifyMiddleReadingPosition(reference: true)
    }

    func testCatalogMiddleReadingPositionAcrossDirectionChanges() throws {
        try verifyMiddleReadingPosition(reference: false)
    }

    private func verifyMiddleReadingPosition(reference: Bool) throws {
        continueAfterFailure = false
        try XCTSkipIf(XCUIScreen.screens.count < 2, "需要 Duo 展开内屏")
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US"]
        if reference { app.launchArguments.append("-catalog-scroll-swiftui-reference") }
        app.launch()
        for pose in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            let label = "\(reference ? "swiftui" : "kit")-\(pose.rawValue)"
            print("ReadingPose \(label)")
            XCUIDevice.shared.orientation = pose
            let window = app.windows.firstMatch
            waitUntil(timeout: 90) {
                (window.frame.width > window.frame.height) == pose.isLandscape
                    && self.matchesDuoScreenOrientation(pose)
            }
            let list = app.collectionViews.firstMatch
            showDirectoryIfNeeded(app, list: list)
            try dragToMiddle(app: app, list: list)
            var baseline: ReadingPosition?
            for step in 0..<3 {
                if step > 0 {
                    switchLanguage(in: app, rtl: step == 1)
                    showDirectoryIfNeeded(app, list: list)
                }
                let title = step == 1 ? "الأمثلة" : "Examples"
                waitUntil { app.navigationBars[title].exists }
                let position = try settledPosition(app: app, list: list)
                print("ReadingPosition \(label) step=\(step) id=\(position.id) offset=\(position.offset) height=\(position.height) top=\(position.top)")
                let image = XCTAttachment(screenshot: XCUIScreen.screens[1].screenshot())
                image.name = "reading-\(label)-\(step)"
                image.lifetime = .keepAlways
                add(image)
                if let baseline {
                    XCTAssertEqual(position.id, baseline.id, label)
                    // 译文较短且原偏移会遮住整行时，比较仍露出的行尾；切回后必须恢复原偏移。
                    let expected = step == 1 && baseline.offset <= -position.height
                        ? min(position.height, max(1, baseline.height + baseline.offset)) - position.height
                        : baseline.offset
                    XCTAssertEqual(position.offset, expected, accuracy: 1, label)
                } else {
                    baseline = position
                }
            }
        }
        app.terminate()
    }

    private func showDirectoryIfNeeded(_ app: XCUIApplication, list: XCUIElement) {
        let button = app.buttons["Show Sidebar"]
        if button.exists && button.isHittable { button.tap() }
        waitUntil { list.exists && app.windows.firstMatch.frame.intersects(list.frame) }
    }

    private func readingTop(app: XCUIApplication, list: XCUIElement) -> CGFloat {
        let viewport = list.frame
        let centerX = viewport.midX
        // 排除详情栏的导航栏。搜索框可能单独占一行，覆盖区域也不属于可阅读视口。
        let chrome = app.navigationBars.allElementsBoundByIndex + app.searchFields.allElementsBoundByIndex
        return chrome.map(\.frame).filter { $0.minX <= centerX && $0.maxX >= centerX && $0.minY < viewport.midY }
            .reduce(viewport.minY) { max($0, $1.maxY) }
    }

    private func dragToMiddle(app: XCUIApplication, list: XCUIElement) throws {
        let window = app.windows.firstMatch
        let viewport = list.frame
        let bounds = window.frame
        func point(_ y: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: (viewport.midX - bounds.minX) / bounds.width,
                                                            dy: (y - bounds.minY) / bounds.height))
        }
        // 各姿态的行高和长标题换行不同。以中段实际露出的首行为基准，切换后逐点比较。
        let middle = ["demo.geometry.title", "demo.arrangement.title", "demo.directionalGrid.title",
                      "demo.horizontalScroll.title", "demo.dynamicScroll.title", "demo.keyboard.title"]
        for _ in 0..<8 {
            let first = try settledPosition(app: app, list: list)
            if first.id == "demo.safeAreaPadding.title" { break }
            point(viewport.minY + viewport.height * 0.33).press(forDuration: 0.08,
                thenDragTo: point(viewport.minY + viewport.height * 0.81), withVelocity: 650, thenHoldForDuration: 0.3)
        }
        for _ in 0..<10 {
            let mid = viewport.midY
            point(mid + 78).press(forDuration: 0.08, thenDragTo: point(mid - 78),
                                  withVelocity: 420, thenHoldForDuration: 0.3)
            let first = try settledPosition(app: app, list: list)
            if middle.contains(first.id) { return }
        }
        XCTFail("真实拖动未到达目录中段")
    }

    private func settledPosition(app: XCUIApplication, list: XCUIElement) throws -> ReadingPosition {
        func sample() throws -> ReadingPosition {
            let top = readingTop(app: app, list: list)
            let snapshot = try list.snapshot()
            func routes(_ node: XCUIElementSnapshot) -> [(String, CGRect)] {
                if node.identifier.hasPrefix("demo."), node.identifier.hasSuffix(".title") {
                    return [(node.identifier, node.frame)]
                }
                return node.children.flatMap(routes)
            }
            let row = try XCTUnwrap(routes(snapshot).filter { $0.1.maxY > top + 0.5 && $0.1.minY < snapshot.frame.maxY }
                .min { $0.1.minY < $1.1.minY })
            return ReadingPosition(id: row.0, offset: row.1.minY - top, height: row.1.height, top: top)
        }
        var previous = try sample()
        for _ in 0..<5 {
            let next = try sample()
            if previous.id == next.id && abs(previous.offset - next.offset) < 0.5 { return next }
            previous = next
        }
        XCTFail("松手后目录位置未稳定")
        return previous
    }

    private func switchLanguage(in app: XCUIApplication, rtl: Bool) {
        let buttons = app.buttons.matching(identifier: "demo.language.menu")
        let window = app.windows.firstMatch
        if !buttons.allElementsBoundByIndex.contains(where: { $0.isHittable }),
           window.frame.height > window.frame.width {
            // 覆盖式目录过窄时地球按钮被收到“更多”里。点目录外收起它，使用详情导航栏的语言菜单。
            let sidebarOnRight = app.collectionViews.firstMatch.frame.midX > window.frame.midX
            window.coordinate(withNormalizedOffset: CGVector(dx: sidebarOnRight ? 0.20 : 0.80, dy: 0.45)).tap()
        }
        let menu = buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(menu, app.debugDescription)
        menu?.tap()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", rtl ? "العربية" : "English")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    private func measure(_ app: XCUIApplication, rtl: Bool, landscape: Bool, name: String) throws -> Measurement {
        let list = app.collectionViews.firstMatch
        let row = list.descendants(matching: .any).matching(identifier: "demo.safeAreaPadding.title").firstMatch
        let title = rtl ? "حشوة المنطقة الآمنة" : "Safe Area Padding"
        // Duo 的竖屏可能把目录收进系统侧栏；与用户一样，通过导航按钮展开后再拖动。
        if !landscape, !row.exists || !row.isHittable {
            let sidebar = app.buttons["Show Sidebar"]
            if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        }
        waitUntil { row.exists && row.label == title && row.isHittable }
        let viewport = list.frame
        if landscape {
            XCTAssertLessThan(viewport.width, app.windows.firstMatch.frame.width * 0.65, name)
            XCTAssertEqual(viewport.midX > app.windows.firstMatch.frame.midX, rtl, name)
        }
        let before = row.frame
        if !rtl { try verifyEnglishGlyphs(row: before, window: app.windows.firstMatch.frame, name: name) }
        // 从分组标题开始往返，避免横拖被没有横向行程的单元格当作点选。
        let window = app.windows.firstMatch
        let bounds = window.frame
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: (x - bounds.minX) / bounds.width,
                                                            dy: (y - bounds.minY) / bounds.height))
        }
        let y = before.minY - 8
        let left = point(before.minX + before.width * 0.20, y)
        let right = point(before.minX + before.width * 0.78, y)
        for (a, b) in [(left, right), (right, left)] {
            a.press(forDuration: 0.08, thenDragTo: b, withVelocity: 220, thenHoldForDuration: 0.2)
            XCTAssertEqual(row.frame.minX, before.minX, accuracy: 1, name)
            XCTAssertEqual(row.frame.maxX, before.maxX, accuracy: 1, name)
        }
        // 直接使用已测得的窗口坐标，避免覆盖式侧栏在手势过程中重复解析相对坐标。
        let start = point(before.midX, viewport.minY + viewport.height * 0.68)
        let end = point(before.midX, viewport.minY + viewport.height * 0.44)
        let marker = list.descendants(matching: .any).matching(identifier: "demo.viewThatFits.title").firstMatch
        XCTAssertTrue(marker.isHittable, name)
        let initialY = marker.frame.minY
        print("CatalogVertical \(name)")
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: 380, thenHoldForDuration: 0.3)
        let afterY = marker.frame.minY
        print("CatalogVerticalOffset \(name) before=\(initialY) after=\(afterY)")
        XCTAssertLessThan(afterY, initialY - 12, name)
        let bars = list.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label CONTAINS %@ OR label CONTAINS %@",
            "Vertical scroll bar", "شريط التمرير", "شريط تمرير"))
        let track = try XCTUnwrap(bars.allElementsBoundByIndex.first { $0.frame.height > $0.frame.width }, list.debugDescription).frame
        let result = Measurement(viewport: viewport, left: before.minX - viewport.minX,
                                 right: viewport.maxX - before.maxX, indicatorOnLeft: track.midX < viewport.midX)
        // 系统可拖动热区宽于灰条，方向切换时它的原点也会变，单独验证它处于正确的一侧。
        XCTAssertEqual(result.indicatorOnLeft, rtl, name)
        // 亮屏原图中的灰条宽 3 pt，离列边缘 3 pt。热区应覆盖这个位置。
        let visibleCenter = rtl ? viewport.minX + 4.5 : viewport.maxX - 4.5
        XCTAssertLessThanOrEqual(track.minX, visibleCenter, name)
        XCTAssertGreaterThanOrEqual(track.maxX, visibleCenter, name)
        print("CatalogMeasured \(name) viewport=\(viewport) margins=\(result.left),\(result.right) track=\(track)")
        let image = XCTAttachment(screenshot: XCUIScreen.screens[1].screenshot())
        image.name = "catalog-" + name
        image.lifetime = .keepAlways
        add(image)
        // 让下一个语言或姿态从同一行开始，同时实测相反方向的纵向拖动。
        end.press(forDuration: 0.08, thenDragTo: point(before.midX, viewport.minY + viewport.height * 0.82),
                  withVelocity: 380, thenHoldForDuration: 0.15)
        waitUntil { row.isHittable && abs(row.frame.minY - before.minY) <= 1 }
        return result
    }

    /// 可访问性字符串不会反映字形镜像。直接识别当前亮屏首行，覆盖切回英文的绘制结果。
    private func verifyEnglishGlyphs(row: CGRect, window: CGRect, name: String) throws {
        let shot = XCUIScreen.screens[1].screenshot()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(shot.pngRepresentation as CFData, nil))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 3000]
        let image = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
        let sx = CGFloat(image.width) / window.width
        let sy = CGFloat(image.height) / window.height
        XCTAssertEqual(sx, sy, accuracy: 0.02, name)
        let crop = try XCTUnwrap(image.cropping(to: row.offsetBy(dx: -window.minX, dy: -window.minY)
            .applying(CGAffineTransform(scaleX: sx, y: sy)).integral))
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: crop).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        print("CatalogGlyphs \(name) text=\(text)")
        XCTAssertTrue(text.lowercased().filter(\.isLetter).contains("safeareapadding"), "\(name) 实际首行：\(text)")
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }
}
