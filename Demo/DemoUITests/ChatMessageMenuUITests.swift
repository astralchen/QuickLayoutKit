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
        if name.contains("preview") {
            let settled = expectation(description: "Preview drawing completes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    @MainActor private func preview(in app: XCUIApplication) -> XCUIElement {
        let content = app.descendants(matching: .any).matching(identifier: "imessage.menu.preview").firstMatch
        // iOS 26 的菜单只向 UI 自动化暴露系统预览容器；iOS 27 还包含离屏内容控制器。
        return content.exists ? content : app.otherElements.matching(NSPredicate(format: "label IN %@", ["Preview", "预览"])).firstMatch
    }

    @MainActor private func tapPreview(in app: XCUIApplication) {
        // UIKit 将内容控制器放在屏幕外渲染，实际命中对象是系统预览容器。
        let container = app.otherElements.matching(NSPredicate(format: "label IN %@", ["Preview", "预览"])).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 4))
        container.tap()
    }

    @MainActor private func assertPreviewAspectRatio(_ ratio: CGFloat, in app: XCUIApplication) {
        let container = app.otherElements.matching(NSPredicate(format: "label IN %@", ["Preview", "预览"])).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in
            let frame = container.frame
            return frame.height > 0 && abs(frame.width / frame.height - ratio) < 0.015
        }, evaluatedWith: container)
        waitForExpectations(timeout: 10)
    }

    @MainActor func testImageGIFAndRotatedVideoFilePreviewAspectRatios() throws {
        for (fixture, ratio) in [("preview-image-file", 0.75), ("preview-gif-file", 1.0), ("preview-video-file", 0.75)] {
            let app = open(["-imessage-save-fixture", fixture])
            let file = app.buttons["imessage.attachment.file.card"]
            XCTAssertTrue(file.waitForExistence(timeout: 10))
            file.press(forDuration: 1.1)
            assertPreviewAspectRatio(ratio, in: app)
            XCTAssertTrue(menu("share", in: app).exists)
            capture(app, fixture + "-aspect-preview")
            tapPreview(in: app)
            XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
            app.terminate()
        }
    }

    @MainActor private func waitForPreviewMotion(in app: XCUIApplication) {
        let container = app.otherElements.matching(NSPredicate(format: "label IN %@", ["Preview", "预览"])).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 6))
        let first = container.screenshot().pngRepresentation
        expectation(for: NSPredicate { _, _ in container.screenshot().pngRepresentation != first }, evaluatedWith: container)
        waitForExpectations(timeout: 8)
    }

    @MainActor func testPhotoPreviewCommitsCurrentGroupItem() throws {
        let app = open(["-imessage-save-fixture", "stack5"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        media.swipeLeft()
        media.press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(menu("save", in: app).exists)
        capture(app, "photo-content-preview")
        tapPreview(in: app)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["imessage.preview.position"].label, "Item 2 of 5")
        capture(app, "photo-preview-committed")
        app.buttons["imessage.media.preview.close"].tap()
        XCTAssertTrue(media.waitForExistence(timeout: 5))
    }

    @MainActor func testVideoPreviewAutoplaysAndCommits() throws {
        let app = open(["-imessage-save-fixture", "resources-draft"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 15))
        media.press(forDuration: 1.1)
        let content = preview(in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 6))
        waitForPreviewMotion(in: app)
        capture(app, "video-playing-preview")
        tapPreview(in: app)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
        capture(app, "video-preview-committed")
        app.buttons["imessage.media.preview.close"].tap()
    }

    @MainActor func testBundledVideoWithAudioPreviewStopsOnDismissal() throws {
        let app = open(["-imessage-save-fixture", "resources-draft"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20))
        media.press(forDuration: 1.1)
        let content = preview(in: app)
        XCTAssertTrue(content.waitForExistence(timeout: 6))
        waitForPreviewMotion(in: app)
        capture(app, "audible-video-playing")
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(content.waitForNonExistence(timeout: 5))
        capture(app, "audible-video-dismissed")
    }

    @MainActor func testMediaPreviewLandscapeRTLAndLargeText() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = open(["-imessage-save-fixture", "stack5",
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], locale: "ar")
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 15))
        let visible = media.frame.intersection(app.collectionViews["imessage.timeline"].frame)
        XCTAssertFalse(visible.isNull)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 6))
        capture(app, "landscape-rtl-large-preview")
        tapPreview(in: app)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
        app.buttons["imessage.media.preview.close"].tap()
        XCTAssertTrue(media.waitForExistence(timeout: 5))
    }

    @MainActor func testLivePhotoWithAudioPreviewAndDismissal() throws {
        let app = open(["-imessage-save-fixture", "resources-live-audio"])
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20))
        media.press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Share Originals"].exists)
        let container = app.otherElements.matching(NSPredicate(format: "label IN %@", ["Preview", "预览"])).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 4))
        // 包内实况照片为 480 × 640；系统最终展示的预览也必须保持 3:4。
        XCTAssertEqual(container.frame.width / container.frame.height, 0.75, accuracy: 0.015)
        capture(app, "audible-live-preview")
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(preview(in: app).waitForNonExistence(timeout: 4))
        capture(app, "audible-live-dismissed")
        media.press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 6))
        tapPreview(in: app)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
        capture(app, "audible-live-committed")
        app.buttons["imessage.media.preview.close"].tap()
    }

    @MainActor func testPDFPreviewAndAudioFileFallback() throws {
        var app = open(["-imessage-save-fixture", "document"])
        var file = app.buttons["imessage.attachment.file.card"]
        XCTAssertTrue(file.waitForExistence(timeout: 8))
        file.press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 5))
        assertPreviewAspectRatio(1.5, in: app)
        capture(app, "pdf-content-preview")
        tapPreview(in: app)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 8))
        app.terminate()
        app = open(["-imessage-save-fixture", "audio"])
        file = app.buttons["imessage.attachment.file.card"]
        XCTAssertTrue(file.waitForExistence(timeout: 8))
        file.press(forDuration: 1.1)
        XCTAssertTrue(menu("share", in: app).waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "imessage.menu.preview").firstMatch.exists)
        capture(app, "audio-file-no-preview")
    }

    @MainActor func testWebPreviewLoadsRealPageAndCancels() throws {
        let app = open(["-imessage-menu-fixture", "-imessage-menu-web"])
        let card = app.buttons["imessage.attachment.link.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.press(forDuration: 1.1)
        XCTAssertTrue(preview(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Link"].exists)
        let web = app.webViews["imessage.menu.preview.web"]
        XCTAssertTrue(web.waitForExistence(timeout: 20))
        XCTAssertTrue(web.links.firstMatch.waitForExistence(timeout: 20), "The actual webpage must load beyond the title placeholder")
        capture(app, "web-content-preview")
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(preview(in: app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(card.exists)
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
