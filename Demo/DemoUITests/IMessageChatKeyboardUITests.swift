import XCTest

final class IMessageChatKeyboardUITests: XCTestCase {
    @MainActor
    func testKeyboardToPhotoMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
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
