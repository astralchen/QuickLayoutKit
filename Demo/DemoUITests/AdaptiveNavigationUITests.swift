import XCTest
import UIKit

/// 在 iPad 和 iPhone 上运行同一组用例，验证双栏与原生返回导航。
final class AdaptiveNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// 检查原生项目边界，并留存各选中态截图以核对符号和文字基线。
    @MainActor func testTabSelectionKeepsItemsAligned() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Three root tabs require iOS 26") }
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let identifiers = ["examples", "chat", "voiceRoom"]
        let items = identifiers.map { app.buttons.matching(identifier: "app.tab.\($0)").firstMatch }
        for item in items { XCTAssertTrue(item.waitForExistence(timeout: 10)) }
        for index in [0, 1, 2, 0] {
            items[index].tap()
            waitFor(app) { items[index].isSelected }
            let frames = items.map(\.frame)
            for (item, frame) in zip(items, frames) {
                XCTAssertTrue(item.isHittable)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertEqual(frame.midY, frames[0].midY, accuracy: 1)
                XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX)
            }
            capture(app, "tabs-portrait-\(identifiers[index])")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitFor(app) { app.frame.width > app.frame.height }
        for item in items {
            XCTAssertTrue(item.isHittable)
            XCTAssertEqual(item.frame.midY, items[0].frame.midY, accuracy: 1)
        }
        capture(app, "tabs-landscape")
    }

    @MainActor func testDemoContentStaysInsideDetailColumn() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let pages = [
            ("UIKit", "demo.uikitLocalization.title"),
            ("Directional", "demo.directionalNavigation.title"),
            ("Semantic Gestures", "demo.semanticGesture.title"),
            ("Refresh Boundaries", "demo.localizationBoundary.title"),
            ("Keyboard Layout", "demo.keyboard.title"),
        ]
        for (query, identifier) in pages {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { search.tap() }
            let clear = search.buttons.firstMatch
            if clear.exists { clear.tap() }
            search.typeText(query)
            let route = app.cells[identifier]
            XCTAssertTrue(route.waitForExistence(timeout: 5))
            route.tap()
            let content = identifier == "demo.keyboard.title"
                ? app.textFields["keyboard.input"] : app.staticTexts["localization.demo.body"]
            XCTAssertTrue(content.waitForExistence(timeout: 5))
            let minimumX = route.isHittable ? route.frame.maxX : app.frame.minX
            XCTAssertGreaterThanOrEqual(content.frame.minX, minimumX)
            XCTAssertLessThanOrEqual(content.frame.maxX, app.frame.maxX)
            XCTAssertTrue(content.isHittable)
            capture(app, identifier + "-portrait")
            if identifier == "demo.keyboard.title" {
                content.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                content.typeText("Adaptive layout")
                let submit = app.buttons["keyboard.submit"]
                XCTAssertLessThanOrEqual(submit.frame.maxY, app.keyboards.firstMatch.frame.minY)
                submit.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
                XCUIDevice.shared.orientation = .landscapeLeft
                waitFor(app) { app.frame.width > app.frame.height }
                let landscapeMinimumX = route.isHittable ? route.frame.maxX : app.frame.minX
                XCTAssertGreaterThanOrEqual(content.frame.minX, landscapeMinimumX)
                XCTAssertLessThanOrEqual(content.frame.maxX, app.frame.maxX)
                capture(app, "keyboard-layout-landscape")
            } else if !route.isHittable {
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(route.waitForExistence(timeout: 5))
            }
        }
    }

    @MainActor func testExampleNavigationAndRotation() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        waitFor(app) { search.isHittable }
        search.tap()
        // 首次显示的大标题搜索栏可能仍在完成容器布局，确认焦点后再输入。
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            search.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Counter")
        let route = app.cells["demo.counter.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let increment = app.buttons["counter.increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        XCTAssertTrue(increment.isHittable)
        increment.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(route.isHittable, "宽窗口必须同时显示目录和详情")
            XCTAssertLessThan(route.frame.maxX, increment.frame.minX)
        } else {
            XCTAssertFalse(route.isHittable, "紧凑窗口应显示详情")
        }
        capture(app, "navigation-portrait")
        app.buttons.matching(identifier: "app.tab.voiceRoom").firstMatch.tap()
        XCTAssertTrue(app.buttons["liveRoom.gift.button"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "app.tab.examples").firstMatch.tap()
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        XCTAssertTrue(increment.isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitFor(app) { app.frame.width > app.frame.height && app.navigationBars["Counter"].exists }
        // 矮窗口中详情按设计滚动；验证按钮可滚动到达，而非要求所有内容同时可见。
        for _ in 0..<3 where !increment.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(increment.isHittable)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(route.isHittable)
            XCTAssertLessThan(route.frame.maxX, increment.frame.minX)
        }
        capture(app, "navigation-landscape")
        XCUIDevice.shared.orientation = .portrait
        if UIDevice.current.userInterfaceIdiom == .phone {
            waitFor(app) { app.frame.height > app.frame.width && increment.isHittable }
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(route.waitForExistence(timeout: 5))
            XCTAssertTrue(route.isHittable)
            XCTAssertEqual(search.value as? String, "Counter")
            route.tap()
            XCTAssertTrue(increment.waitForExistence(timeout: 5))
            XCTAssertTrue(increment.isHittable)
            capture(app, "navigation-return-and-reopen")
        }
    }

    @MainActor func testRootChatPreservesDraftAcrossTabs() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Chat requires iOS 26") }
        let app = launch()
        let chat = app.buttons.matching(identifier: "app.tab.chat").firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        let editor = app.textViews["imessage.composer.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Navigation draft")
        let timeline = app.collectionViews["imessage.timeline"]
        // interactive 收起需要手指越过键盘边缘；普通 swipeDown 在空列表内结束会回弹。
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        let examples = app.buttons.matching(identifier: "app.tab.examples").firstMatch
        waitFor(app) { examples.isHittable }
        XCTAssertTrue(examples.isHittable)
        examples.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        chat.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Navigation draft")
        capture(app, "navigation-chat-draft-preserved")
    }

    @MainActor private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", "en-US",
                                "-imessage-basic-history", "-chat-draft-session", UUID().uuidString]
        app.launch()
        return app
    }

    @MainActor private func waitFor(_ app: XCUIApplication, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // 捕获完整屏幕，避免旋转后的应用元素截图被裁切。
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
