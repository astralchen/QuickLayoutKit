import XCTest

final class AdaptivePanelUITests: XCTestCase {
    private var expectedOrientation: String?

    /// 使用系统窗口右下角的真实拖动，不能用修改内容视图 frame 冒充多窗口验收。
    @MainActor func testIPadWindowResizePreservesSelection() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("仅用于 iPad 窗口缩放") }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Adaptive Panel")
        app.cells["demo.adaptivePanel.title"].tap()
        let hideSidebar = app.buttons["Hide Sidebar"]
        if hideSidebar.exists, hideSidebar.isHittable { hideSidebar.tap() }
        app.segmentedControls["panel.detent"].buttons["medium"].tap()
        app.buttons["panel.open"].tap()
        let row = app.cells["panel.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(row.isSelected)
        let window = app.windows.firstMatch
        let original = window.frame
        defer {
            let current = window.frame
            if current.size != original.size {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995)).press(forDuration: 0.5,
                    thenDragTo: window.coordinate(withNormalizedOffset: .zero).withOffset(
                        CGVector(dx: original.maxX - current.minX - 2, dy: original.maxY - current.minY - 2)))
            }
        }
        let diagnostics = app.staticTexts["panel.diagnostics"]
        let before = diagnostics.label
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995)).press(forDuration: 0.5,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "iPad 系统窗口缩放后"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertTrue(waitUntil { abs(window.frame.width - original.width) > 40 || abs(window.frame.height - original.height) > 40 })
        XCTAssertTrue(waitForStableGeometry(diagnostics))
        XCTAssertNotEqual(before, diagnostics.label)
        XCTAssertTrue(row.isSelected)
        XCTAssertTrue(app.buttons["panel.close"].isHittable)
        print("PANEL_WINDOW_RESIZE \(original) -> \(window.frame) | \(diagnostics.label)")
    }

    @MainActor func testAllDetentsInPortrait() throws {
        let device = XCUIDevice.shared
        let original = device.orientation
        expectedOrientation = "纵屏"
        defer { device.orientation = original; expectedOrientation = nil }
        device.orientation = .portrait
        try testAllDetentsInCurrentPose()
    }

    @MainActor func testAllDetentsInLandscape() throws {
        let device = XCUIDevice.shared
        let original = device.orientation
        expectedOrientation = "横屏"
        defer { device.orientation = original; expectedOrientation = nil }
        device.orientation = .landscapeLeft
        try testAllDetentsInCurrentPose()
    }

    /// 不发送旋转指令，保留 Device Hub 设置的姿态和折叠角度，逐档保存实际画面。
    @MainActor func testAllDetentsInCurrentPose() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Adaptive Panel")
        app.cells["demo.adaptivePanel.title"].tap()
        let hideSidebar = app.buttons["Hide Sidebar"]
        if hideSidebar.exists, hideSidebar.isHittable { hideSidebar.tap() }
        var measurements: [String: [String: String]] = [:]
        for engine in ["UIKit", "QuickLayoutKit"] {
            app.segmentedControls["panel.engine"].buttons[engine].tap()
            for detent in ["1/3", "medium", "large"] {
                let selection = app.segmentedControls["panel.detent"].buttons[detent]
                if !selection.isHittable { app.scrollViews.firstMatch.swipeUp() }
                selection.tap()
                let open = app.buttons["panel.open"]
                if !open.isHittable { app.scrollViews.firstMatch.swipeDown() }
                open.tap()
                let diagnostics = app.staticTexts["panel.diagnostics"]
                XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
                XCTAssertTrue(waitUntil { app.buttons["panel.close"].isHittable })
                XCTAssertTrue(waitForStableGeometry(diagnostics))
                if let expectedOrientation { XCTAssertTrue(diagnostics.label.contains(expectedOrientation)) }
                XCTAssertTrue(diagnostics.label.contains("horizontalSizeClass:"))
                XCTAssertTrue(diagnostics.label.contains("verticalSizeClass:"))
                measurements[engine, default: [:]][detent] = diagnostics.label
                print("PANEL_MATRIX \(engine) requested=\(detent) \(diagnostics.label.replacingOccurrences(of: "\n", with: " | "))")
                let record = XCTAttachment(string: diagnostics.label)
                record.name = "当前姿态-\(engine)-\(detent)"
                record.lifetime = .keepAlways
                add(record)
                // Duo 展开时 main 可能仍指向熄灭的外屏，必须保存所有活动显示器。
                for (index, screen) in XCUIScreen.screens.enumerated() {
                    let screenshot = XCTAttachment(screenshot: screen.screenshot())
                    screenshot.name = "\(record.name ?? "面板")-display\(index)"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
                app.buttons["panel.close"].tap()
                XCTAssertTrue(waitUntil { !diagnostics.exists })
            }
        }
        // Duo 的各姿态直接以本次 UIKit 为基准，不保存设备固定尺寸。
        for detent in ["1/3", "medium", "large"] {
            if let native = measurements["UIKit"]?[detent], let custom = measurements["QuickLayoutKit"]?[detent],
               native.contains("openLandscape") || native.contains("openPortrait") || native.contains("closed")
                || native.contains(" · book · ") || native.contains(" · tabletop · ") {
                let nativeLines = native.split(separator: "\n")
                let customLines = custom.split(separator: "\n")
                XCTAssertEqual(nativeLines.first { $0.hasPrefix("面板 ") }, customLines.first { $0.hasPrefix("面板 ") })
                XCTAssertEqual(nativeLines.first { $0.hasPrefix("位置 ") }, customLines.first { $0.hasPrefix("位置 ") })
            }
        }
    }

    @MainActor func testNonmodalInteractionDragAndNativeComparison() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Adaptive Panel")
        app.cells["demo.adaptivePanel.title"].tap()
        let hideSidebar = app.buttons["Hide Sidebar"]
        if hideSidebar.exists, hideSidebar.isHittable { hideSidebar.tap() }
        let open = app.buttons["panel.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let list = app.tables["panel.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let background = app.buttons["panel.background"]
        background.tap()
        XCTAssertTrue(background.label.contains("1"))
        let grabber = app.otherElements["adaptivePanel.grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 3))
        let initialHeight = list.frame.height
        let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -240)))
        XCTAssertTrue(waitUntil { list.frame.height > initialHeight + 40 })
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "组件拖动展开"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["panel.close"].tap()
        XCTAssertTrue(waitUntil { !list.exists })
        app.segmentedControls["panel.engine"].buttons["UIKit"].tap()
        app.segmentedControls["panel.detent"].buttons["1/3"].tap()
        open.tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        background.tap()
        XCTAssertTrue(background.label.contains("2"))
        let native = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        native.name = "系统非模态 Sheet"
        native.lifetime = .keepAlways
        add(native)
        let nativeSmallHeight = list.frame.height
        app.buttons["panel.close"].tap()
        XCTAssertTrue(waitUntil { !list.exists })
        app.segmentedControls["panel.detent"].buttons["large"].tap()
        open.tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { list.frame.height > nativeSmallHeight + 40 })
        app.buttons["panel.close"].tap()
    }

    @MainActor func testScrollingKeyboardAndRotationPreserveContent() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let originalOrientation = device.orientation
        defer { device.orientation = originalOrientation }
        device.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        openPanelExample(in: app)
        let open = app.buttons["panel.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        app.segmentedControls["panel.detent"].buttons["medium"].tap()
        open.tap()
        let list = app.tables["panel.list"]
        let diagnostics = app.staticTexts["panel.diagnostics"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStableGeometry(diagnostics))
        let initialHeight = list.frame.height
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -list.frame.height * 0.9)))
        XCTAssertTrue(waitUntil { list.frame.height > initialHeight + 40 }, diagnostics.label)
        XCTAssertTrue(waitForStableGeometry(diagnostics))
        let input = app.textFields["panel.input"]
        input.tap()
        let keyboard = app.keyboards.firstMatch
        let exists = keyboard.waitForExistence(timeout: 5)
        print("PANEL_KEYBOARD", "windows", app.windows.allElementsBoundByIndex.map(\.frame), "keyboards", app.keyboards.allElementsBoundByIndex.map(\.frame), "input", input.debugDescription)
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let evidence = XCTAttachment(screenshot: screen.screenshot())
            evidence.name = "点击输入框-display\(index)"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(exists)
        XCTAssertTrue(waitUntil { keyboard.frame.intersection(app.windows.firstMatch.frame).height > 100 })
        XCTAssertTrue(waitUntil { input.frame.maxY <= keyboard.frame.minY + 1 })
        // 使用屏幕按键，确保输入期间软件键盘持续显示。
        for letter in ["p", "a", "n", "e", "l"] {
            keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch.tap()
        }
        let enteredText = input.value as? String
        XCTAssertEqual(enteredText?.lowercased(), "panel")
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let typed = XCTAttachment(screenshot: screen.screenshot())
            typed.name = "实际键盘输入-display\(index)"
            typed.lifetime = .keepAlways
            add(typed)
        }
        XCTAssertTrue(diagnostics.label.contains("纵屏"), "需要从实际纵屏开始旋转验收")
        device.orientation = .landscapeLeft
        // Duo 可通过 Device Hub 旋转实际亮屏。只以页面最终方向判断旋转是否完成。
        let landscape = NSPredicate { _, _ in MainActor.assumeIsolated { diagnostics.label.contains("横屏") } }
        let rotated = XCTNSPredicateExpectation(predicate: landscape, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: diagnostics.label.contains(" · closed · ") ? 45 : 5), .completed)
        XCTAssertTrue(waitUntil { input.value as? String == enteredText && input.isHittable })
        XCTAssertTrue(waitUntil {
            keyboard.exists && keyboard.frame.intersection(app.windows.firstMatch.frame).height > 100
                && input.frame.maxY <= keyboard.frame.minY + 1
        }, "旋转后输入框应在可见软件键盘上方")
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let evidence = XCTAttachment(screenshot: screen.screenshot())
            evidence.name = "旋转后保留输入与键盘-display\(index)"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        app.buttons["panel.close"].tap()
        XCTAssertTrue(waitUntil { !list.exists })
    }

    /// 在 Device Hub 中从展开横屏开始，依次半开、旋转、展开、旋转。日志提示采样完成后再切换。
    @MainActor func testDuoKeyboardAcrossPoses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-panel-geometry-measurements", "-panel-literal-keyboard-input", "-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        openPanelExample(in: app)
        let diagnostics = app.staticTexts["panel.diagnostics"]
        let input = app.textFields["panel.input"]
        let keyboard = app.keyboards.firstMatch
        let poses = ["openLandscape", "book", "tabletop", "openPortrait", "openLandscape"]
        let letters = ["l", "a", "n", "e", "t"]
        var reference: [[Double]] = []
        var actual: [[Double]] = []
        for engine in ["UIKit", "QuickLayoutKit"] {
            app.segmentedControls["panel.engine"].buttons[engine].tap()
            app.segmentedControls["panel.detent"].buttons["medium"].tap()
            app.buttons["panel.open"].tap()
            XCTAssertTrue(diagnostics.waitForExistence(timeout: 8))
            guard diagnostics.label.contains("openLandscape") else { throw XCTSkip("需要从 Duo 展开横屏开始并使用 Device Hub 切换姿态") }
            input.tap()
            XCTAssertTrue(waitUntil { keyboard.exists && keyboard.frame.intersection(app.windows.firstMatch.frame).height > 100 }, input.debugDescription)
            func tapKey(_ letter: String) {
                keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch.tap()
            }
            tapKey("p")
            var entered = "p"
            for (index, pose) in poses.enumerated() {
                let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { diagnostics.label.contains(" · " + pose + " · ") } }
                let changed = XCTNSPredicateExpectation(predicate: predicate, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 90), .completed, "\(engine) 等待 \(pose)")
                XCTAssertTrue(waitForStableGeometry(diagnostics))
                XCTAssertTrue(waitUntil { keyboard.exists && keyboard.frame.intersection(app.windows.firstMatch.frame).height > 100 },
                              "\(engine) \(pose) 需要保持屏幕键盘可见")
                // 键盘和面板分别完成转场。逐键确认可编辑，再等键盘自身的边界稳定后采样。
                XCTAssertEqual((input.value as? String)?.lowercased(), entered)
                tapKey(letters[index])
                entered += letters[index]
                XCTAssertEqual((input.value as? String)?.lowercased(), entered)
                var lastKeyboardFrame = keyboard.frame
                var stableSince = Date()
                XCTAssertTrue(waitUntil {
                    guard keyboard.exists else { return false }
                    let current = keyboard.frame
                    if current != lastKeyboardFrame {
                        lastKeyboardFrame = current
                        stableSince = Date()
                    }
                    return Date().timeIntervalSince(stableSince) >= 1
                })
                let frame = keyboard.frame
                let window = app.windows.firstMatch.frame
                let record = "\(engine) \(index) \(pose) | \(diagnostics.label) | 键盘 \(frame) | 输入框 \(input.frame) | 文本 \(input.value ?? "")"
                print("DUO_KEYBOARD", record.replacingOccurrences(of: "\n", with: " | "))
                for (display, screen) in XCUIScreen.screens.enumerated() {
                    let shot = XCTAttachment(screenshot: screen.screenshot())
                    shot.name = "\(engine)-\(index)-\(pose)-display\(display)"
                    shot.lifetime = .keepAlways
                    add(shot)
                }
                XCTAssertEqual((input.value as? String)?.lowercased(), entered)
                XCTAssertTrue(keyboard.exists && frame.intersection(window).height > 100, record)
                XCTAssertTrue(input.isHittable && input.frame.maxY <= frame.minY + 1, record)
                let firstLine = try XCTUnwrap(diagnostics.label.split(separator: "\n").first)
                let degrees = try XCTUnwrap(Double(firstLine.components(separatedBy: "折叠角度 ").last?.replacingOccurrences(of: "°", with: "") ?? ""))
                if pose.hasPrefix("open") { XCTAssertEqual(degrees, 180, accuracy: 1) }
                else { XCTAssertTrue(degrees > 0 && degrees < 179) }
                let geometry = (diagnostics.value as? String)?.split(separator: ",").compactMap { Double($0) } ?? []
                XCTAssertEqual(geometry.count, 5)
                let inputFrame = input.frame
                // 比较键盘上方可见的列表，捕捉转场后沿用旧键盘高度造成的空白。
                let table = app.tables["panel.list"].frame
                let visibleListBottom = min(table.maxY, frame.minY)
                print("DUO_LIST", engine, pose, table, visibleListBottom)
                let measurement = geometry + [frame.minX, frame.minY, frame.width, frame.height,
                                              inputFrame.minX, inputFrame.minY, inputFrame.width, inputFrame.height, visibleListBottom].map(Double.init) + [degrees]
                XCTAssertTrue(diagnostics.label.contains(" · " + pose + " · "), "姿态应在采样结束前保持稳定")
                if engine == "UIKit" { reference.append(measurement) } else { actual.append(measurement) }
                print("DUO_POSE_READY", engine, index, pose)
            }
            app.buttons["panel.close"].tap()
            XCTAssertTrue(waitUntil { !diagnostics.exists })
        }
        continueAfterFailure = true
        for index in poses.indices {
            for (value, expected) in zip(actual[index], reference[index]) {
                XCTAssertEqual(value, expected, accuracy: 1, "\(poses[index]) 面板、最大高度、键盘、输入框及角度：\(actual[index]) vs \(reference[index])")
            }
        }
    }

    /// 在同一设备姿态下比较两个实现的纵横屏尺寸；姿态由 Device Hub 控制。
    @MainActor func testContainerSizingComparison() throws {
        try compareRotations(detent: "1/3")
    }

    @MainActor func testIPadMediumAndLargeAfterRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("仅用于 iPad 页面旋转对照") }
        try compareRotations(detent: "medium")
        try compareRotations(detent: "large")
    }

    @MainActor private func compareRotations(detent: String) throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let original = device.orientation
        defer { device.orientation = original }
        device.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-panel-geometry-measurements", "-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en"]
        app.launch()
        openPanelExample(in: app)
        var reference: [[Double]] = []
        for engine in ["UIKit", "QuickLayoutKit"] {
            app.segmentedControls["panel.engine"].buttons[engine].tap()
            app.segmentedControls["panel.detent"].buttons[detent].tap()
            app.buttons["panel.open"].tap()
            let diagnostics = app.staticTexts["panel.diagnostics"]
            XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
            for (index, orientation) in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait].enumerated() {
                device.orientation = orientation
                let direction = orientation == .portrait ? "纵屏" : "横屏"
                XCTAssertTrue(waitUntil { diagnostics.label.contains(direction) })
                // 等待实际布局稳定，再读取面板中的实时诊断文本。
                XCTAssertTrue(waitForStableGeometry(diagnostics))
                if UIDevice.current.userInterfaceIdiom == .pad {
                    let values = (diagnostics.value as? String)?.split(separator: ",").compactMap { Double($0) } ?? []
                    XCTAssertEqual(values.count, 5)
                    if engine == "UIKit" { reference.append(values) }
                    else if reference.indices.contains(index) {
                        for (actual, expected) in zip(values, reference[index]) {
                            XCTAssertEqual(actual, expected, accuracy: 1, "\(direction) x/y/宽/高/最大高度：\(values) vs \(reference[index])")
                        }
                    }
                }
                let record = XCTAttachment(string: diagnostics.label)
                record.name = "尺寸对照-\(engine)-\(direction)"
                record.lifetime = .keepAlways
                add(record)
                print("PANEL_GEOMETRY \(diagnostics.label.replacingOccurrences(of: "\n", with: " | "))")
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = record.name
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            app.buttons["panel.close"].tap()
            XCTAssertTrue(waitUntil { !diagnostics.exists })
        }
    }

    @MainActor private func openPanelExample(in app: XCUIApplication) {
        // 宽屏分栏可能恢复上一次已选中的详情页。
        if app.buttons["panel.open"].isHittable { return }
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.waitForExistence(timeout: 2), sidebar.isHittable { sidebar.tap() }
        // 先从目录进入；快速滚过该分组时，通过目录搜索定位同一路由。
        let menu = app.collectionViews.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        let route = app.cells["demo.adaptivePanel.title"]
        for _ in 0..<12 where !route.isHittable { menu.swipeUp() }
        if !route.isHittable {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.isHittable, app.debugDescription)
            search.tap()
            search.typeText("Adaptive Panel")
        }
        XCTAssertTrue(route.isHittable)
        route.tap()
        let hideSidebar = app.buttons["Hide Sidebar"]
        if hideSidebar.exists, hideSidebar.isHittable { hideSidebar.tap() }
    }

    @MainActor private func waitUntil(_ condition: @escaping @MainActor () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    /// 至少连续稳定一秒才取证，避免方向已更新、转场几何仍在变化时保存中间帧。
    @MainActor private func waitForStableGeometry(_ diagnostics: XCUIElement) -> Bool {
        var previous = diagnostics.label
        var unchangedSince = Date()
        return waitUntil {
            let current = diagnostics.label
            if current != previous {
                previous = current
                unchangedSince = Date()
                return false
            }
            return diagnostics.isHittable && Date().timeIntervalSince(unchangedSince) >= 1
        }
    }
}
