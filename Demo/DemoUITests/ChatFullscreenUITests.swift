import XCTest
import UIKit

final class ChatFullscreenUITests: XCTestCase {
    override func setUpWithError() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Chat requires iOS 26") }
        continueAfterFailure = false
    }

    @MainActor func testFullScreenThroughKeyboardAndBack() throws {
        let app = openChat()
        defer { XCUIDevice.shared.orientation = .portrait }
        let list = app.collectionViews["imessage.timeline"]
        let editor = app.textViews["imessage.composer.text"]
        assertFullScreen(list, in: app)
        capture(app, "全屏聊天-竖屏")
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        editor.typeText("Full screen\nMultiline message")
        assertFullScreen(list, in: app)
        let composer = app.otherElements["imessage.composer"]
        // 外接键盘下 AX 仍可能保留屏幕外的 Keyboard 节点，不能用 exists 判断停靠键盘。
        let keyboardFrame = app.keyboards.firstMatch.frame.intersection(app.frame)
        let hasSoftwareKeyboard = !keyboardFrame.isNull && keyboardFrame.height > 100
        if hasSoftwareKeyboard {
            XCTAssertLessThanOrEqual(composer.frame.maxY, keyboardFrame.minY + 1)
        } else {
            XCTAssertLessThanOrEqual(composer.frame.maxY, app.frame.maxY)
            XCTAssertTrue(editor.isHittable)
        }
        capture(app, hasSoftwareKeyboard ? "全屏聊天-多行输入与软件键盘" : "全屏聊天-多行输入与外接键盘")
        app.buttons["imessage.composer.send"].tap()
        XCTAssertEqual(editor.value as? String, "")
        // 从列表可见中段向下拖动，验证悬浮输入栏没有接管整个页面的触摸。
        if hasSoftwareKeyboard {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            let hiddenKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let keyboard = app.keyboards.firstMatch
                return !keyboard.exists || keyboard.frame.intersection(app.frame).height < 100
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [hiddenKeyboard], timeout: 5), .completed)
        }
        assertFullScreen(list, in: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.cells["demo.imessage.title"].waitForExistence(timeout: 5))
    }

    @MainActor func testFullScreenAfterRotation() throws {
        let app = openChat()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height && app.textViews["imessage.composer.text"].isHittable
        }, object: app)
        if XCTWaiter.wait(for: [landscape], timeout: 10) != .completed {
            // iPad 窗口模式可能保持原窗口尺寸；先在未修改的首页确认同一限制。
            if UIDevice.current.userInterfaceIdiom == .pad {
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.cells["demo.imessage.title"].waitForExistence(timeout: 5))
                let mainRotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.frame.width > app.frame.height
                }, object: app)
                if XCTWaiter.wait(for: [mainRotated], timeout: 5) != .completed {
                    throw XCTSkip("iPad 宿主窗口在首页和聊天页均未响应设备旋转；窗口尺寸变化另由布局测试覆盖")
                }
            }
            XCTFail("聊天窗口未完成横屏布局")
            return
        }
        assertFullScreen(app.collectionViews["imessage.timeline"], in: app)
        capture(app, "全屏聊天-横屏")
    }

    @MainActor func testDarkLargeRTLFullScreen() {
        let app = openChat(rtl: true)
        assertFullScreen(app.collectionViews["imessage.timeline"], in: app)
        capture(app, "全屏聊天-深色大字体RTL")
    }

    @MainActor func testCancelledBackSwipePreservesDraftAndHistory() {
        let app = openChat()
        let editor = app.textViews["imessage.composer.text"]
        editor.tap()
        editor.typeText("History before cancelled back")
        app.buttons["imessage.composer.send"].tap()
        editor.typeText("Preserved draft")
        let list = app.collectionViews["imessage.timeline"]
        let count = list.cells.count
        // 慢速短距离侧滑并停住后松开，使原生返回转场取消。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.4))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.4)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Preserved draft")
        XCTAssertGreaterThanOrEqual(list.cells.count, count)
        assertFullScreen(list, in: app)
        editor.tap()
        editor.typeText(" continues")
        XCTAssertEqual(editor.value as? String, "Preserved draft continues")
        capture(app, "全屏聊天-取消返回后继续编辑")
    }

    @MainActor private func openChat(rtl: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let language = rtl ? "ar" : "zh-Hans"
        app.launchArguments += ["-imessage-basic-history", "-AppleLanguages", "(\(language))",
                                "-quicklayoutkit.demo.locale.identifier", language]
        if rtl {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                    "-AppleInterfaceStyle", "Dark"]
        }
        app.launch()
        let route = app.cells["demo.imessage.title"]
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<10 where !route.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        XCTAssertTrue(app.textViews["imessage.composer.text"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func assertFullScreen(_ list: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(list.frame.minX, window.minX, accuracy: 1)
        XCTAssertEqual(list.frame.minY, window.minY, accuracy: 1)
        XCTAssertEqual(list.frame.width, window.width, accuracy: 1)
        XCTAssertEqual(list.frame.height, window.height, accuracy: 1)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // 捕获实际屏幕，避免旋转后 application 截图仍按旧方向裁切。
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
