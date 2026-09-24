import XCTest

/// 经首页进入真实实验室验证操作；外观截图沿用测试设备当前的浅色／深色设置。
final class FrameLabUITests: XCTestCase {
    /// 检查三语名称、模式顺序、默认选中与往返切换，并保留首屏及完整代码区截图。
    @MainActor func testPresentationAppearance() throws {
        continueAfterFailure = false
        for (locale, freeformTitle, guidedTitle, modeLabel) in [
            ("zh-Hans", "自由实验", "引导实验", "实验模式"),
            ("en", "Freeform", "Guided", "Experiment mode"),
            ("ar", "تجربة حرة", "تجربة موجّهة", "نمط التجربة")
        ] {
            let app = try openLab(locale: locale)
            let presentation = app.segmentedControls["frame.presentation"]
            let freeform = presentation.buttons[freeformTitle]
            let guided = presentation.buttons[guidedTitle]
            XCTAssertEqual(presentation.label, modeLabel)
            XCTAssertTrue(freeform.isSelected)
            XCTAssertTrue(guided.isHittable)
            if locale == "ar" { XCTAssertGreaterThan(freeform.frame.minX, guided.frame.minX) }
            else { XCTAssertLessThan(freeform.frame.minX, guided.frame.minX) }
            capture(app, "frame-lab-\(locale)-freeform")
            guided.tap()
            XCTAssertTrue(guided.isSelected)
            capture(app, "frame-lab-\(locale)-guided")
            let code = app.staticTexts["frame.code"]
            for _ in 0..<4 where !code.isHittable || !app.windows.firstMatch.frame.contains(code.frame) { app.swipeUp() }
            XCTAssertTrue(code.isHittable)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(code.frame))
            XCTAssertTrue(presentation.isHittable)
            capture(app, "frame-lab-\(locale)-guided-controls-code")
            freeform.tap()
            XCTAssertTrue(freeform.isSelected)
            app.terminate()
        }
    }

    /// 通过实际操作验证独立状态／滚动恢复、六场景导航、更多参数、复制与当前模式重置。
    @MainActor func testPresentationSwitchingAndGuidedExperiments() throws {
        continueAfterFailure = false
        let app = try openLab(locale: "zh-Hans")
        let presentation = app.segmentedControls["frame.presentation"]
        let switchFrame = presentation.frame
        let code = app.staticTexts["frame.code"]
        app.segmentedControls["frame.options"].buttons["仅宽度"].tap()
        for _ in 0..<4 where !app.sliders["frame.width"].isHittable { app.swipeUp() }
        app.sliders["frame.width"].adjust(toNormalizedSliderPosition: 0.3)
        let firstWidth = app.sliders["frame.width"].value as? String
        for _ in 0..<4 where !code.isHittable { app.swipeUp() }
        let firstCode = code.label
        let codeY = code.frame.minY
        XCTAssertEqual(presentation.frame, switchFrame)
        capture(app, "frame-lab-option1-code")

        presentation.buttons["引导实验"].tap()
        capture(app, "frame-lab-option3-default")
        app.buttons["frame.scenario"].tap()
        app.buttons["固定尺寸"].firstMatch.tap()
        XCTAssertTrue(app.segmentedControls["frame.options"].buttons["双轴"].isSelected)
        XCTAssertFalse(app.buttons["frame.previous"].isEnabled)
        let more = app.buttons["frame.more"]
        for _ in 0..<4 where !more.isHittable { app.swipeUp() }
        more.tap()
        let width = app.sliders["frame.width"]
        // 将整条滑块移离 Home 手势区，避免底部横向拖动触发系统切换应用。
        for _ in 0..<4 where !width.isHittable || width.frame.maxY > app.windows.firstMatch.frame.maxY - 120 {
            app.swipeUp()
        }
        let right = width.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let left = width.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.1)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.1)
        let guidedWidth = width.value as? String
        presentation.buttons["自由实验"].tap()
        XCTAssertEqual(code.label, firstCode)
        XCTAssertEqual(code.frame.minY, codeY, accuracy: 2)
        XCTAssertEqual(app.sliders["frame.width"].value as? String, firstWidth)
        presentation.buttons["引导实验"].tap()
        XCTAssertEqual(app.sliders["frame.width"].value as? String, guidedWidth)
        XCTAssertEqual(more.value as? String, "已展开")

        for index in 0..<6 {
            let selector = app.buttons["frame.scenario"]
            for _ in 0..<5 where !selector.isHittable { app.swipeDown() }
            if index == 4 {
                let alignment = app.buttons["frame.alignment.topLeading"]
                for _ in 0..<4 where !alignment.isHittable { app.swipeUp() }
                alignment.tap()
                XCTAssertTrue(alignment.isSelected)
                capture(app, "frame-lab-option3-alignment")
            }
            if index == 5 { XCTAssertFalse(app.buttons["frame.next"].isEnabled) }
            else {
                for _ in 0..<5 where !app.buttons["frame.next"].isHittable { app.swipeDown() }
                app.buttons["frame.next"].tap()
            }
        }
        for _ in 0..<5 where !app.buttons["frame.copy"].isHittable { app.swipeUp() }
        app.buttons["frame.copy"].tap()
        XCTAssertEqual(app.buttons["frame.copy"].value as? String, "代码已复制")
        capture(app, "frame-lab-option3-code")
        app.buttons["frame.reset"].tap()
        presentation.buttons["自由实验"].tap()
        XCTAssertEqual(code.label, firstCode)
        XCTAssertEqual(app.sliders["frame.width"].value as? String, firstWidth)
        XCTAssertEqual(presentation.frame, switchFrame)
    }

    /// 按阿拉伯语标题选择模式，验证引导实验中九宫格及真实内容的前缘位于右侧。
    @MainActor func testGuidedArabicAlignment() throws {
        let app = try openLab(locale: "ar")
        app.segmentedControls["frame.presentation"].buttons["تجربة موجّهة"].tap()
        app.buttons["frame.scenario"].tap()
        app.buttons["المحاذاة"].firstMatch.tap()
        let leading = app.buttons["frame.alignment.topLeading"]
        for _ in 0..<4 where !leading.isHittable { app.swipeUp() }
        leading.tap()
        XCTAssertTrue(leading.isSelected)
        let trailing = app.buttons["frame.alignment.topTrailing"]
        XCTAssertGreaterThan(leading.frame.minX, trailing.frame.minX)
        XCTAssertEqual(app.staticTexts["frame.sample"].frame.maxX, app.otherElements["frame.preview"].frame.maxX, accuracy: 2)
        capture(app, "frame-lab-option3-arabic")
    }

    /// 实际往返拖动宽度，验证选中项保持、预览持续响应；视图身份由布局回归另行断言。
    @MainActor func testWidthDraggingKeepsSelectionAndUpdatesPreview() throws {
        continueAfterFailure = false
        let app = try openLab(locale: "zh-Hans")
        let width = app.sliders["frame.width"]
        let options = app.segmentedControls["frame.options"]
        let preview = app.otherElements["frame.preview"]
        let initialWidth = preview.frame.width
        let right = width.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let left = width.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        for _ in 0..<2 {
            right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertTrue(options.buttons["双轴"].isSelected)
            XCTAssertLessThan(preview.frame.width, initialWidth * 0.65)
            left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertTrue(options.buttons["双轴"].isSelected)
            XCTAssertGreaterThan(preview.frame.width, initialWidth * 0.85)
        }
        capture(app, "frame-lab-width-dragging")
    }

    /// 覆盖自由实验六场景、主要选项、尺寸与拉伸、复制反馈及重置。
    @MainActor func testExperimentsAndControls() throws {
        continueAfterFailure = false
        let app = try openLab(locale: "zh-Hans")
        capture(app, "frame-lab-default")
        let code = app.staticTexts["frame.code"]
        for _ in 0..<4 where !code.isHittable { app.swipeUp() }
        XCTAssertTrue(code.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(code.frame))
        capture(app, "frame-lab-code")
        for _ in 0..<4 where !app.buttons["frame.scenario"].isHittable { app.swipeDown() }
        let options = app.segmentedControls["frame.options"]
        options.buttons["仅宽度"].tap()
        options.buttons["双轴"].tap()
        app.sliders["frame.width"].adjust(toNormalizedSliderPosition: 0.4)
        app.sliders["frame.height"].adjust(toNormalizedSliderPosition: 0.6)
        app.switches["frame.stretch"].tap()
        capture(app, "frame-lab-stretched")

        for title in ["最小／最大尺寸", "理想尺寸", "撑满空间", "对齐", "链式组合"] {
            // 滚回场景选择器，避免不同场景高度影响控件可达性。
            let selector = app.buttons["frame.scenario"]
            for _ in 0..<3 where !selector.isHittable { app.swipeDown() }
            selector.tap()
            app.buttons[title].firstMatch.tap()
            if title == "理想尺寸" { options.buttons["未指定"].tap() }
            if title == "对齐" {
                app.buttons["frame.alignment"].tap()
                app.buttons["底部后缘"].tap()
            }
            if title == "链式组合" { options.buttons["先 frame"].tap() }
            capture(app, "frame-lab-\(title)")
        }
        let copy = app.buttons["frame.copy"]
        for _ in 0..<4 where !copy.isHittable { app.swipeUp() }
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertEqual(copy.value as? String, "代码已复制")
        app.buttons["frame.reset"].tap()
        for _ in 0..<4 where !app.buttons["frame.scenario"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.segmentedControls["frame.options"].buttons["双轴"].isSelected)
        capture(app, "frame-lab-reset")
    }

    /// 验证自由实验的阿拉伯语对齐菜单与实际内容位置。
    @MainActor func testArabicAlignment() throws {
        let app = try openLab(locale: "ar")
        app.buttons["frame.scenario"].tap()
        app.buttons["المحاذاة"].firstMatch.tap()
        app.buttons["frame.alignment"].tap()
        app.buttons["أعلى البداية"].tap()
        capture(app, "frame-lab-arabic-alignment")
        let sample = app.staticTexts["frame.sample"]
        XCTAssertTrue(sample.exists)
        let preview = app.otherElements["frame.preview"]
        XCTAssertEqual(sample.frame.maxX, preview.frame.maxX, accuracy: 2)
    }

    /// 同时设置系统语言和应用语言覆盖值，从首页路由进入，避免跳过入口接入验证。
    @MainActor private func openLab(locale: String) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(locale))", "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        let route = app.cells["demo.frame.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        for _ in 0..<4 where !route.isHittable { app.swipeUp() }
        route.tap()
        XCTAssertTrue(app.buttons["frame.scenario"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
