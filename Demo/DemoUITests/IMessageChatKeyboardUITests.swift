import XCTest

final class IMessageChatKeyboardUITests: XCTestCase {
    @MainActor
    func testDraftShowsRecordingHintAndRestoresKeyboard() throws {
        try verifyRecordingHint(language: "zh-Hans", audioTitle: "音频", draft: "draft")
    }

    @MainActor
    func testRecordingHintInRTLAtAccessibilityTextSize() throws {
        try verifyRecordingHint(language: "ar", audioTitle: "صوت", largeText: true)
    }

    @MainActor
    private func verifyRecordingHint(
        language: String,
        audioTitle: String,
        largeText: Bool = false,
        draft: String = "draft\nsecond line"
    ) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-quicklayoutkit.demo.locale.identifier", language,
        ]
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        let route = app.cells["demo.imessage.title"]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<8 where !route.exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(route.exists)
        route.tap()
        let text = app.textViews["imessage.composer.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.tap()
        text.typeText(draft)
        let composer = app.otherElements["imessage.composer"]
        let originalFrame = composer.frame
        let attachment = app.buttons["imessage.composer.attachment"]
        attachment.tap()
        app.buttons[audioTitle].tap()
        let hint = app.staticTexts["imessage.composer.recordingUnavailable"]
        // XCTest 的菜单退场等待可能超过两秒；瞬时状态与时长由受控计时测试验证。
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["imessage.composer.recording.stop"].exists)
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5))
        XCTAssertEqual(text.value as? String, draft)
        XCTAssertTrue(attachment.isEnabled)
        XCTAssertTrue(app.buttons["imessage.composer.send"].isEnabled)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(composer.frame.maxY, originalFrame.maxY, accuracy: 1)
        XCTAssertEqual(composer.frame.height, originalFrame.height, accuracy: 1)
        if !draft.contains("\n") {
            XCTAssertEqual(
                app.buttons["imessage.composer.send"].frame.midY,
                text.frame.midY,
                accuracy: 0.5
            )
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "录音提示后草稿与键盘恢复-\(language)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testKeyboardToPhotoMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-quicklayoutkit.demo.locale.identifier", "zh-Hans",
        ]
        app.launch()
        let route = app.cells["demo.imessage.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        let text = app.textViews["imessage.composer.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let composer = app.otherElements["imessage.composer"]
        let keyboardComposerBottom = composer.frame.maxY
        // 必须实际经过附件菜单；直接调用照片控制器不会产生菜单关闭时的临时键盘通知。
        let attachment = app.buttons["imessage.composer.attachment"]
        attachment.tap()
        app.buttons["照片"].tap()
        // 通过系统面板的控制柄验证真实边界，覆盖附件菜单关闭时的焦点恢复。
        let grabber = app.buttons["表单控制柄"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 10))
        let aligned = NSPredicate { _, _ in
            composer.frame.maxY <= grabber.frame.midY + 1
                && abs(composer.frame.maxY - keyboardComposerBottom) <= 1
        }
        expectation(for: aligned, evaluatedWith: composer)
        waitForExpectations(timeout: 10)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "键盘切换照片选择器"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("照片面板边界: 键盘时底边=\(keyboardComposerBottom), 照片时底边=\(composer.frame.maxY), 控制柄中心=\(grabber.frame.midY)")
    }
}
