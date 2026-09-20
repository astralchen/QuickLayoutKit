import XCTest

final class ChatMessageMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Chat requires iOS 26 or later") }
    }

    @MainActor private func open(_ arguments: [String] = ["-imessage-menu-fixture"], locale: String = "en") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += arguments + ["-AppleLanguages", "(en)", "-quicklayoutkit.demo.locale.identifier", locale]
        app.launch()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        let route = app.cells["demo.imessage.title"]
        if arguments.contains("-UIPreferredContentSizeCategoryName") {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("iMessage\n")
        } else {
            for _ in 0..<10 where !route.exists { app.collectionViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        XCTAssertTrue(app.textViews["imessage.composer.text"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func menu(_ operation: String, in app: XCUIApplication) -> XCUIElement {
        let titles: [String: [String]] = [
            "copy": ["Copy", "Copy Still Photo", "Copy Transcript", "Copy Link", "拷贝", "拷贝静态照片", "拷贝转写文本", "拷贝链接"],
            "selectText": ["Select Text", "选择文本"], "delete": ["Delete", "删除"],
            "share": ["Share", "Share Originals", "分享", "分享原件"],
            "save": ["Save Photo", "Save Animated Image", "Save Live Photo", "Save Video", "Save to Files", "存储照片", "存储动图", "存储实况照片", "存储视频", "存储到文件"]
        ]
        return app.buttons.matching(NSPredicate(format: "label IN %@", titles[operation] ?? [])).firstMatch
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MessageMenu-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testTextCopyDeleteCancelAndSelection() throws {
        let app = open()
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Bold menu text")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.press(forDuration: 1.1)
        capture(app, "long-press-before-query")
        XCTAssertTrue(menu("copy", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(menu("selectText", in: app).exists)
        XCTAssertFalse(menu("save", in: app).exists)
        capture(app, "text-menu")
        menu("copy", in: app).tap()
        let editor = app.textViews["imessage.composer.text"]
        editor.tap()
        editor.press(forDuration: 1.1)
        let paste = app.buttons["Paste"]
        if paste.waitForExistence(timeout: 2) { paste.tap() }
        else { app.menuItems["Paste"].tap() }
        XCTAssertEqual(editor.value as? String, "Bold menu text")
        text.press(forDuration: 1.1)
        XCTAssertTrue(menu("delete", in: app).waitForExistence(timeout: 4))
        menu("delete", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(text.exists)
        text.press(forDuration: 1.1)
        XCTAssertTrue(menu("selectText", in: app).waitForExistence(timeout: 4))
        menu("selectText", in: app).tap()
        let copy = app.buttons["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3) || app.menuItems["Copy"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture(app, "text-selection")
        editor.tap()
        XCTAssertEqual(editor.value as? String, "Bold menu text")
        text.press(forDuration: 1.1)
        XCTAssertTrue(menu("delete", in: app).waitForExistence(timeout: 4))
        menu("delete", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "label == %@", "Menu text https://www.apple.com")).firstMatch.exists)
        capture(app, "after-delete")
    }

    @MainActor func testDetectedLinkLongPressUsesMessageMenu() throws {
        let app = open()
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Menu text https://www.apple.com")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.65)).press(forDuration: 1.1)
        XCTAssertTrue(menu("selectText", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(menu("share", in: app).exists)
        capture(app, "detected-link-menu")
    }

    @MainActor func testDetectedLinkSingleTapOpensSystemBrowser() throws {
        let app = open()
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Menu text https://www.apple.com")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.65)).tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 8))
        app.activate()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertFalse(menu("selectText", in: app).exists)
    }

    @MainActor func testMediaMenuFollowsCoverAndGroupDeletionIsExplicit() throws {
        let app = open(["-imessage-save-fixture", "resources-live"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20))
        media.press(forDuration: 1.1)
        XCTAssertTrue(menu("save", in: app).waitForExistence(timeout: 4))
        XCTAssertEqual(menu("save", in: app).label, "Save Live Photo")
        XCTAssertEqual(menu("share", in: app).label, "Share Originals")
        capture(app, "live-photo-menu")
        // Outside dismissal must leave the current cover and playback unchanged.
        app.navigationBars.firstMatch.tap()
        media.swipeLeft()
        media.press(forDuration: 1.1)
        XCTAssertTrue(menu("save", in: app).waitForExistence(timeout: 4))
        XCTAssertEqual(menu("save", in: app).label, "Save Photo")
        XCTAssertEqual(menu("share", in: app).label, "Share")
        capture(app, "current-photo-menu")
        menu("delete", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.alerts.staticTexts["The entire message and all its items will be removed from the current conversation only."].exists)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(media.exists)
    }

    @MainActor func testFileSharePresentsSystemSheet() throws {
        let app = open(["-imessage-save-fixture", "document"])
        let file = app.buttons["imessage.attachment.file.card"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        file.press(forDuration: 1.1)
        XCTAssertTrue(menu("share", in: app).waitForExistence(timeout: 4))
        XCTAssertFalse(menu("copy", in: app).exists)
        menu("share", in: app).tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 8)
                      || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists)
        capture(app, "file-share")
    }

    @MainActor func testChineseMenu() throws {
        let app = open(locale: "zh-Hans")
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Bold menu text")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.press(forDuration: 1.1)
        capture(app, "long-press-before-query")
        XCTAssertTrue(menu("copy", in: app).waitForExistence(timeout: 4))
        XCTAssertEqual(menu("copy", in: app).label, "拷贝")
        XCTAssertEqual(menu("selectText", in: app).label, "选择文本")
        XCTAssertEqual(menu("delete", in: app).label, "删除")
        capture(app, "chinese-menu")
    }
    @MainActor func testLargeRTLMenuStaysWithinScreen() throws {
        let app = open(["-imessage-menu-fixture", "-UIPreferredContentSizeCategoryName",
                        "UICTContentSizeCategoryAccessibilityXXXL"], locale: "ar")
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Bold menu text")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.press(forDuration: 1.1)
        let select = app.buttons["تحديد النص"]
        XCTAssertTrue(select.waitForExistence(timeout: 4))
        let delete = app.buttons["حذف"]
        XCTAssertTrue(delete.isHittable)
        XCTAssertGreaterThanOrEqual(delete.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(delete.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(delete.frame.maxY, app.frame.maxY)
        capture(app, "large-RTL")
    }

    @MainActor func testFailureMenuRetriesSameMessage() throws {
        let app = open(["-imessage-basic-history", "-imessage-fail-first-send"])
        let editor = app.textViews["imessage.composer.text"]
        editor.tap()
        editor.typeText("Retry menu message")
        app.buttons["imessage.composer.send"].tap()
        let text = app.textViews.matching(NSPredicate(format: "label == %@", "Retry menu message")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.press(forDuration: 1.1)
        let retry = app.buttons["Send Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 4))
        capture(app, "failed-message")
        retry.tap()
        XCTAssertTrue(text.exists)
        text.press(forDuration: 1.1)
        XCTAssertTrue(menu("copy", in: app).waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Send Again"].exists)
    }

    /// 使用包内生成的实况／GIF 原件，真实等待 Photos 写入成功后的菜单完成反馈。
    @MainActor func testSaveCurrentLivePhotoAndGIFToPhotos() throws {
        guard ProcessInfo.processInfo.environment["CHAT_MENU_PHOTOS_WRITE"] == "1" else {
            throw XCTSkip("Opt in with TEST_RUNNER_CHAT_MENU_PHOTOS_WRITE=1; this writes two fixture assets to Photos")
        }
        let app = open(["-imessage-save-fixture", "resources-live"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20))
        for title in ["Save Live Photo", "Save Animated Image"] {
            media.press(forDuration: 0.6)
            let save = app.buttons[title]
            XCTAssertTrue(save.waitForExistence(timeout: 4))
            save.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.alerts.firstMatch.exists {
                let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", [
                    "Allow Adding Photos", "Allow Adding Photos Only", "Allow Photos to be Added", "Allow Access to Add Photos", "Allow", "OK",
                    "允许添加照片", "仅允许添加照片", "允许添加", "允许", "好"
                ])).firstMatch
                XCTAssertTrue(allow.waitForExistence(timeout: 2))
                allow.tap()
            }
            media.press(forDuration: 0.6)
            XCTAssertTrue(app.buttons["Saved"].exists || app.buttons["Saved"].waitForExistence(timeout: 3), "Photos must report success, not just dismiss the menu")
            capture(app, title == "Save Live Photo" ? "live-photo-saved" : "gif-saved")
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "Completion feedback must restore the save action in the open menu")
            XCTAssertTrue(app.buttons[title].isEnabled)
            app.navigationBars.firstMatch.tap()
            if title == "Save Live Photo" { media.swipeLeft(); media.swipeLeft() }
        }
    }

}
