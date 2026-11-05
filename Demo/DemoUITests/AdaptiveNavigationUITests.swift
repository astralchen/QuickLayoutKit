import XCTest
import UIKit

/// 在 iPad 和 iPhone 上运行同一组用例，验证双栏与原生返回导航。
final class AdaptiveNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// 拖动 App 内部的 Split 分隔线；不修改列宽属性或注入 trait。
    @MainActor func testSplitColumnDragPreservesSelectionAndSafeContent() throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Interactive split column resizing requires iPadOS 26")
        }
        let app = launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer { XCUIDevice.shared.orientation = .portrait }
        if app.windows.firstMatch.frame.width < system.windows.firstMatch.frame.width - 30 {
            system.buttons["window-controls:com.sondra.Demo"].tap()
            system.buttons["Zoom-button"].firstMatch.tap()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitFor(app) { app.windows.firstMatch.frame.width > 1000 }
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Counter")
        let route = app.cells["demo.counter.title"]
        route.tap()
        let increment = app.buttons["counter.increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<4 where !increment.isHittable { app.scrollViews.firstMatch.swipeUp() }
        increment.tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label == %@ AND value == %@", "Log a glass", "4 of 8 glasses")).firstMatch
        let catalog = app.collectionViews.containing(.cell, identifier: "demo.counter.title").firstMatch
        XCTAssertTrue(catalog.exists)
        let window = app.windows.firstMatch.frame
        capture(app, "split-column-before")
        for (index, offset) in [60.0, -80.0, 40.0].enumerated() {
            let before = catalog.frame
            let origin = system.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: before.maxX, dy: before.midY))
                .press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: before.maxX + offset, dy: before.midY)), withVelocity: .slow, thenHoldForDuration: 0.2)
            waitFor(app) { abs(catalog.frame.width - before.width) > 15 }
            print("SPLIT_COLUMN \(before) -> \(catalog.frame)")
            XCTAssertEqual(app.windows.firstMatch.frame, window, "只调整列宽，窗口保持不变")
            XCTAssertTrue(route.isSelected)
            XCTAssertEqual(search.value as? String, "Counter")
            XCTAssertTrue(count.exists)
            XCTAssertGreaterThanOrEqual(increment.frame.minX, catalog.frame.maxX)
            XCTAssertLessThanOrEqual(increment.frame.maxX, window.maxX)
            capture(app, "split-column-drag-\(index)")
        }
    }

    /// 需要 iPadOS 窗口模式；并排用例的系统选择器需可见“设置”（中文或英文）。
    /// 通过 SpringBoard 窗口边框进行真实触摸缩放，不修改应用的 frame。
    @MainActor func testSystemWindowResizePreservesSelectedExample() throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPadOS 26 system window controls") }
        let app = launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func zoom() {
            system.buttons["window-controls:com.sondra.Demo"].tap()
            let button = system.buttons["Zoom-button"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        if app.windows.firstMatch.frame.width < system.windows.firstMatch.frame.width - 30 {
            zoom()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        waitFor(app) { app.windows.firstMatch.frame.width > 1000 }
        let full = app.windows.firstMatch.frame
        let search = app.searchFields.firstMatch
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Counter")
        app.cells["demo.counter.title"].tap()
        let increment = app.buttons["counter.increment"]
        func revealControls() {
            for _ in 0..<5 {
                let bottomTabs = app.tabBars.firstMatch
                let covered = bottomTabs.exists && bottomTabs.frame.minY > increment.frame.minY && increment.frame.maxY > bottomTabs.frame.minY
                if increment.isHittable && !covered { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(increment.isHittable)
            let tabs = app.tabBars.firstMatch
            if tabs.exists && tabs.frame.minY > increment.frame.minY {
                XCTAssertLessThanOrEqual(increment.frame.maxY, tabs.frame.minY)
            }
        }
        revealControls()
        increment.tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label == %@ AND value == %@", "Log a glass", "4 of 8 glasses")).firstMatch
        XCTAssertTrue(count.exists)
        let origin = system.coordinate(withNormalizedOffset: .zero)
        for (index, size) in [CGSize(width: 560, height: 520), CGSize(width: 500, height: 540), CGSize(width: 420, height: 500), CGSize(width: 650, height: 540)].enumerated() {
            let before = app.windows.firstMatch.frame
            let target = CGPoint(x: min(before.minX + size.width, full.maxX - 80), y: min(before.minY + size.height, full.maxY - 80))
            origin.withOffset(CGVector(dx: before.maxX - 8, dy: before.maxY - 8))
                .press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)), withVelocity: .slow, thenHoldForDuration: 0.2)
            waitFor(app) { abs(app.windows.firstMatch.frame.width - before.width) > 20 }
            print("SYSTEM_WINDOW step \(index): \(before) -> \(app.windows.firstMatch.frame)")
            revealControls()
            XCTAssertTrue(count.exists, "窗口缩放必须保留已修改的计数")
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(increment.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(increment.frame.maxX, window.maxX)
            capture(app, "system-window-resize-\(index)")
            let route = app.cells["demo.counter.title"]
            if window.width < 600 && !route.isHittable {
                app.navigationBars["Counter"].buttons.firstMatch.tap()
                waitFor(app) { route.isHittable }
                XCTAssertFalse(route.isSelected, "折叠后返回目录不保留侧栏高亮")
                XCTAssertEqual(search.value as? String, "Counter")
                capture(app, "system-window-collapsed-menu-\(index)")
                route.tap()
                revealControls()
                XCTAssertTrue(count.exists, "返回目录再进入必须复用详情状态")
            }
        }
        if app.windows.firstMatch.frame.width < full.width - 30 { zoom() }
        waitFor(app) { app.windows.firstMatch.frame.width == full.width }
        revealControls()
        XCTAssertTrue(count.exists)
        XCTAssertTrue(app.cells["demo.counter.title"].isHittable)
        XCTAssertTrue(app.cells["demo.counter.title"].isSelected, "展开后恢复当前详情的目录高亮")
        capture(app, "system-window-restored")
    }

    @MainActor func testSystemTilingPreservesNavigationAndSearchFocus() throws {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPadOS 26 system window controls") }
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if app.windows.firstMatch.frame.width < system.windows.firstMatch.frame.width - 30 {
            system.buttons["window-controls:com.sondra.Demo"].tap()
            system.buttons["Zoom-button"].firstMatch.tap()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitFor(app) { app.windows.firstMatch.frame.width > 1000 }
        let frame = app.windows.firstMatch.frame
        let origin = system.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.maxX - 8, dy: frame.maxY - 8))
            .press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY)), withVelocity: .slow, thenHoldForDuration: 0.2)
        system.buttons["window-controls:com.sondra.Demo"].tap()
        system.buttons["Zoom-button"].firstMatch.press(forDuration: 1)
        system.buttons.containing(.image, identifier: "inset.filled.lefthalf.righthalf.rectangle").firstMatch.tap()
        let settingsIcons = system.icons.matching(NSPredicate(format: "identifier IN %@", ["设置", "Settings"]))
        XCTAssertTrue(settingsIcons.firstMatch.waitForExistence(timeout: 5))
        guard let settingsIcon = settingsIcons.allElementsBoundByIndex.first(where: \.isHittable) else { return XCTFail("设置图标不可点击") }
        settingsIcon.tap()
        waitFor(app) { app.windows.firstMatch.frame.minX >= 0 && app.windows.firstMatch.frame.width < 800 }
        // 第二个应用由系统管理；只验证真实窗口，不假定“设置”内部使用 UITableView。
        XCTAssertTrue(system.otherElements["card:com.apple.Preferences:sceneID:com.apple.Preferences-default"].exists)
        XCTAssertTrue(settings.windows.firstMatch.waitForExistence(timeout: 5))
        let right = settings.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(right.minX, app.windows.firstMatch.frame.maxX)
        let search = app.searchFields.firstMatch
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Frame")
        search.buttons["main.search.clear"].tap()
        search.typeText("Counter")
        XCTAssertEqual(search.value as? String, "Counter")
        app.cells["demo.counter.title"].tap()
        let increment = app.buttons["counter.increment"]
        for _ in 0..<4 where !increment.isHittable { app.scrollViews.firstMatch.swipeUp() }
        increment.tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label == %@ AND value == %@", "Log a glass", "4 of 8 glasses")).firstMatch
        XCTAssertTrue(count.exists)
        capture(app, "system-two-apps-search-and-detail")
        for fraction in [0.4, 0.6] {
            let before = app.windows.firstMatch.frame
            let other = settings.windows.firstMatch.frame
            let divider = (before.maxX + other.minX) / 2
            origin.withOffset(CGVector(dx: divider, dy: before.midY))
                .press(forDuration: 0.2, thenDragTo: origin.withOffset(CGVector(dx: system.windows.firstMatch.frame.width * fraction, dy: before.midY)), withVelocity: .slow, thenHoldForDuration: 0.2)
            waitFor(app) { abs(app.windows.firstMatch.frame.width - before.width) > 20 }
            XCTAssertTrue(count.exists)
            print("SYSTEM_TILE \(before) -> \(app.windows.firstMatch.frame)")
            capture(app, "system-divider-\(fraction)")
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        capture(app, "system-two-apps-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        system.buttons["window-controls:com.sondra.Demo"].tap()
        system.buttons["Zoom-button"].firstMatch.tap()
        waitFor(app) { app.windows.firstMatch.frame.width > 1000 }
        XCTAssertTrue(count.exists)
        app.buttons["Hide Sidebar"].tap()
        waitFor(app) { !app.cells["demo.counter.title"].isHittable }
        XCTAssertTrue(count.exists)
        app.buttons["Show Sidebar"].tap()
        waitFor(app) { app.cells["demo.counter.title"].isHittable }
        XCTAssertEqual(search.value as? String, "Counter")
        XCTAssertTrue(count.exists)
        settings.terminate()
        capture(app, "system-tiling-restored")
    }

    @MainActor func testSearchClearKeepsTypingFocusAcrossRotation() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            waitFor(app) { orientation == .portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height }
            for query in ["Frame", "Counter"] {
                search.typeText(query)
                XCTAssertEqual(search.value as? String, query)
                let clear = search.buttons["main.search.clear"]
                XCTAssertTrue(clear.waitForExistence(timeout: 5))
                clear.tap()
                XCTAssertTrue(clear.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.keyboards.firstMatch.exists)
                // 下一次 typeText 直接要求现有焦点，不再点击搜索框。
            }
        }
        search.typeText("Geometry")
        XCTAssertEqual(search.value as? String, "Geometry")
        capture(app, "search-clear-focus-preserved")
    }

    @MainActor func testSwiftUIBridgeScrollsAndPresentsSingleColumnSheet() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { search.tap() }
        search.typeText("SwiftUI")
        let route = app.cells["demo.swiftUIBridge.title"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let show = app.buttons["localization.swiftUI.showSheet"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            waitFor(app) { orientation == .portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height }
            for _ in 0..<3 where !show.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(show.isHittable)
            show.tap()
            let close = app.buttons["localization.swiftUI.closeSheet"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(close.isHittable)
            capture(app, "swiftui-bridge-sheet-\(orientation.rawValue)")
            close.tap()
            XCTAssertTrue(show.waitForExistence(timeout: 5))
        }
    }

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
                // 原生 iPad 顶部 Tab 的 AX 边界是视觉按钮，不代表系统命中区域。
                // 验证实际点击、选中、同高和边界，不将 iPhone 的 44 点外观套给它。
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertEqual(frame.height, frames[0].height, accuracy: 1)
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

    @MainActor func testContentStaysInsideDetailColumn() {
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
            let clear = search.buttons["main.search.clear"]
            if clear.exists {
                clear.tap()
            }
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
