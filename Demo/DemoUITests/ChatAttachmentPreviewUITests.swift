import XCTest

final class ChatAttachmentPreviewUITests: XCTestCase {
    override func setUpWithError() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Attachment preview requires iOS 26") }
        continueAfterFailure = false
    }
    @MainActor private func chat(fixture: String, locale: String = "zh-Hans", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-imessage-save-fixture", fixture, "-quicklayoutkit.demo.locale.identifier", locale] + extra
        app.launch()
        let route = app.cells["demo.imessage.title"]
        for _ in 0..<8 where !route.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()
        XCTAssertTrue(app.textViews["imessage.composer.text"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func openMedia(_ app: XCUIApplication) {
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        media.tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 10))
    }
    @MainActor func testGroupNavigationCancelAndCompleteDismissal() {
        let app = chat(fixture: "stack20")
        openMedia(app)
        let title = app.otherElements["imessage.preview.title"]
        let back = app.buttons["imessage.media.preview.close"]
        let more = app.buttons["imessage.preview.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(back.frame.width, 44, accuracy: 1)
        XCTAssertEqual(more.frame.width, 44, accuracy: 1)
        XCTAssertLessThan(back.frame.maxX, title.frame.minX)
        XCTAssertLessThan(title.frame.maxX, more.frame.minX)
        let position = app.staticTexts["imessage.preview.position"]
        XCTAssertTrue(position.label.contains("20"))
        let firstPosition = position.label
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.45))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(position.label, firstPosition)
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["imessage.preview.thumbnail.1"].isSelected)
        let pages = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imessage.preview.page.")).allElementsBoundByIndex
        let centered = pages.min { abs($0.frame.midX - app.frame.midX) < abs($1.frame.midX - app.frame.midX) }
        XCTAssertNotNil(centered)
        XCTAssertEqual(centered?.frame.minX ?? -100, app.frame.minX, accuracy: 1)
        XCTAssertEqual(centered?.frame.width ?? 0, app.frame.width, accuracy: 1)
        capture(app, "自定义分页-快滑准确停第二页")
        app.buttons["imessage.preview.thumbnail.0"].tap()
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertEqual(position.label, firstPosition)
        capture(app, "居中玻璃顶部-首项")
        more.tap()
        app.buttons["下一个附件"].tap()
        XCTAssertTrue(position.label.contains("2"))
        app.buttons["imessage.preview.thumbnail.1"].tap()
        XCTAssertTrue(position.label.contains("2"))
        capture(app, "玻璃预览-第二项")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(position.label.contains("2"))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(position.label.contains("2"))
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        origin.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)), withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].exists)
        capture(app, "下拉取消-恢复")
        origin.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForNonExistence(timeout: 5))
        openMedia(app)
        XCTAssertTrue(position.label.contains("2"))
        app.buttons["imessage.media.preview.close"].tap()
        capture(app, "收回到当前封面")
    }
    @MainActor func testMediaRowContainsStackBeforeAndAfterPreview() {
        let app = chat(fixture: "stack20")
        func checkGeometry() {
            let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
            let cell = app.cells.containing(.any, identifier: "imessage.media.message").firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(cell.frame.height, media.frame.height)
            XCTAssertGreaterThanOrEqual(media.frame.minY, cell.frame.minY)
            XCTAssertLessThanOrEqual(media.frame.maxY, cell.frame.maxY)
        }
        checkGeometry()
        capture(app, "修复后-媒体行完整占高")
        openMedia(app)
        app.buttons["imessage.preview.thumbnail.1"].tap()
        app.buttons["imessage.media.preview.close"].tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForNonExistence(timeout: 5))
        checkGeometry()
        capture(app, "修复后-预览返回媒体行")
    }

    @MainActor func testSingleImageZoomAndControls() {
        let app = chat(fixture: "photo")
        openMedia(app)
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.doubleTap()
        capture(app, "图片双击放大")
        center.doubleTap()
        center.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: app.buttons["imessage.media.preview.close"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        center.tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 3))
        app.buttons["imessage.media.preview.close"].tap()
    }
    @MainActor func testPDFAndAudioFileUseCustomPreview() {
        for fixture in ["document", "audio", "preview-text"] {
            let app = chat(fixture: fixture)
            let card = app.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 10))
            if fixture == "audio" {
                let play = app.buttons["imessage.preview.play"]
                XCTAssertTrue(play.exists)
                play.tap()
            } else if fixture == "preview-text" {
                let text = app.textViews["imessage.preview.text"]
                XCTAssertTrue(text.waitForExistence(timeout: 5))
                text.swipeUp(velocity: .slow)
                text.swipeDown(velocity: .slow)
                XCTAssertTrue(app.buttons["imessage.media.preview.close"].exists)
            } else {
                let pdf = app.otherElements["imessage.preview.pdf"]
                XCTAssertTrue(pdf.waitForExistence(timeout: 5))
                pdf.pinch(withScale: 2, velocity: 1)
                pdf.swipeUp(velocity: .slow)
                pdf.swipeDown(velocity: .slow)
                XCTAssertTrue(app.buttons["imessage.media.preview.close"].exists)
            }
            capture(app, "自定义文件-\(fixture)")
            app.buttons["imessage.media.preview.close"].tap()
            app.terminate()
        }
    }
    @MainActor func testRTLAndAccessibilitySize() {
        let app = chat(fixture: "stack2", locale: "ar", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openMedia(app)
        capture(app, "RTL-辅助功能最大字号")
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].isHittable)
        XCTAssertTrue(app.buttons["imessage.preview.thumbnail.1"].isHittable)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["imessage.preview.thumbnail.1"].isSelected)
        app.buttons["imessage.media.preview.close"].tap()
    }
    @MainActor func testVideoPlaysInlineAndSeeks() {
        let app = chat(fixture: "preview-video")
        openMedia(app)
        let play = app.buttons["imessage.preview.play"]
        XCTAssertTrue(play.exists)
        play.tap()
        let slider = app.sliders["imessage.preview.progress"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.5)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 3), .completed, "Playback label after seek: \(play.label)")
        app.buttons["imessage.preview.mute"].tap()
        capture(app, "页内视频-进度与静音")
        app.buttons["imessage.media.preview.close"].tap()
    }
    @MainActor func testPhotoAndDocumentDraftReturnPreservesTextAndFocus() {
        for fixture in ["stack2", "preview-text"] {
            let app = chat(fixture: fixture, extra: ["-imessage-preview-draft"])
            let text = app.textViews["imessage.composer.text"]
            text.tap()
            text.typeText("Keep draft")
            if fixture == "stack2" {
                let thumbnail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imessage.composer.media.preview.")).firstMatch
                XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
                thumbnail.tap()
            } else {
                let card = app.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 5))
                card.tap()
            }
            XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 10))
            capture(app, "草稿预览-\(fixture)")
            app.buttons["imessage.media.preview.close"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue((text.value as? String)?.contains("Keep draft") == true)
            app.terminate()
        }
    }
    @MainActor func testQuickLookFallbackAndUnavailableFile() {
        let app = chat(fixture: "preview-rtf", locale: "en")
        app.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["imessage.media.preview.close"].exists)
        capture(app, "QuickLook-兼容文件")
        app.terminate()
        let missing = chat(fixture: "preview-unavailable")
        missing.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch.tap()
        XCTAssertTrue(missing.staticTexts["imessage.preview.message"].waitForExistence(timeout: 10))
        capture(missing, "文件不可用-错误状态")
        missing.buttons["imessage.media.preview.close"].tap()
    }

    @MainActor func testPhotoSheetRemainsAtItsDetent() {
        let app = chat(fixture: "stack2", extra: ["-imessage-preview-draft"])
        let text = app.textViews["imessage.composer.text"]
        text.tap()
        text.typeText("Keep panel")
        app.buttons["imessage.composer.attachment"].tap()
        app.buttons["照片"].tap()
        let grabber = app.buttons["表单控制柄"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 10))
        let before = grabber.frame.midY
        let thumbnail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imessage.composer.media.preview.")).firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        thumbnail.tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 10))
        capture(app, "照片面板上打开预览")
        app.buttons["imessage.media.preview.close"].tap()
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        XCTAssertEqual(grabber.frame.midY, before, accuracy: 1)
        XCTAssertTrue((text.value as? String)?.contains("Keep panel") == true)
        capture(app, "预览返回-照片面板原档位")
    }

    /// 发送媒体和正文后，照片面板继续占据原档位，输入栏仅收起已发送的草稿。
    @MainActor func testSendingKeepsPhotoSheetOpen() {
        let app = chat(fixture: "stack2", extra: ["-imessage-preview-draft"])
        let text = app.textViews["imessage.composer.text"]
        text.tap()
        text.typeText("Keep selecting")
        app.buttons["imessage.composer.attachment"].tap()
        app.buttons["照片"].tap()
        let grabber = app.buttons["表单控制柄"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 10))
        let before = grabber.frame.midY
        capture(app, "连续选图-发送前")
        app.buttons["imessage.composer.send"].tap()
        let thumbnail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imessage.composer.media.preview.")).firstMatch
        XCTAssertTrue(thumbnail.waitForNonExistence(timeout: 5))
        XCTAssertTrue(grabber.exists)
        XCTAssertEqual(grabber.frame.midY, before, accuracy: 1)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse((text.value as? String)?.contains("Keep selecting") == true)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch.exists)
        capture(app, "连续选图-发送后保持面板")
        // 模拟器照片库包含系统样例；连续两次选择同一首格，验证发送会同步取消系统勾选。
        let firstPhoto = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: app.frame.width / 6, dy: before + 70)
        )
        for batch in 1...2 {
            firstPhoto.tap()
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
            let send = app.buttons["imessage.composer.send"]
            let ready = NSPredicate(format: "isEnabled == true")
            expectation(for: ready, evaluatedWith: send)
            waitForExpectations(timeout: 20)
            send.tap()
            XCTAssertTrue(thumbnail.waitForNonExistence(timeout: 5))
            XCTAssertTrue(grabber.exists)
            XCTAssertEqual(grabber.frame.midY, before, accuracy: 1)
            capture(app, "连续选图-第\(batch)批后")
        }
    }

    @MainActor func testSystemReducedMotionAndTransparency() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        func row(_ names: [String]) -> XCUIElement {
            settings.staticTexts.matching(NSPredicate(format: "label IN %@", names)).firstMatch
        }
        func reveal(_ element: XCUIElement) -> Bool {
            for _ in 0..<8 {
                if element.exists && element.isHittable { return true }
                settings.swipeUp()
            }
            return element.exists && element.isHittable
        }
        let accessibility = row(["Accessibility", "辅助功能"])
        guard reveal(accessibility) else { throw XCTSkip("Settings Accessibility entry unavailable") }
        accessibility.tap()
        let motion = row(["Motion", "动态效果"])
        guard reveal(motion) else { throw XCTSkip("Settings Motion entry unavailable") }
        motion.tap()
        let reduceMotion = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "减弱动态效果"])).firstMatch
        guard reduceMotion.waitForExistence(timeout: 5) else { throw XCTSkip("Reduce Motion switch unavailable") }
        let motionWasOn = (reduceMotion.value as? String) == "1"
        if !motionWasOn { reduceMotion.tap() }
        settings.navigationBars.buttons.firstMatch.tap()
        let display = row(["Display & Text Size", "显示与文字大小"])
        guard reveal(display) else {
            motion.tap(); if !motionWasOn { reduceMotion.tap() }
            throw XCTSkip("Display & Text Size unavailable")
        }
        display.tap()
        let transparency = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Transparency", "降低透明度"])).firstMatch
        guard reveal(transparency) else {
            settings.navigationBars.buttons.firstMatch.tap(); motion.tap()
            if !motionWasOn { reduceMotion.tap() }
            throw XCTSkip("Reduce Transparency switch unavailable")
        }
        let transparencyWasOn = (transparency.value as? String) == "1"
        if !transparencyWasOn { transparency.tap() }
        defer {
            settings.activate()
            if !transparencyWasOn, reveal(transparency), (transparency.value as? String) == "1" { transparency.tap() }
            settings.navigationBars.buttons.firstMatch.tap()
            if reveal(motion) {
                motion.tap()
                if !motionWasOn, reduceMotion.exists, (reduceMotion.value as? String) == "1" { reduceMotion.tap() }
                settings.navigationBars.buttons.firstMatch.tap()
            }
            settings.navigationBars.buttons.firstMatch.tap()
            settings.terminate()
        }
        let app = chat(fixture: "stack2")
        openMedia(app)
        app.buttons["imessage.preview.thumbnail.1"].tap()
        XCTAssertTrue(app.buttons["imessage.preview.thumbnail.1"].isSelected)
        capture(app, "系统减少动态效果与降低透明度")
        app.buttons["imessage.media.preview.close"].tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForNonExistence(timeout: 5))
    }

    @MainActor func testLargeTextDocumentClearsGlassHeader() {
        let app = chat(fixture: "preview-text", locale: "ar", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch.tap()
        let text = app.textViews["imessage.preview.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let header = app.otherElements["imessage.preview.title"]
        XCTAssertTrue(header.exists)
        XCTAssertGreaterThanOrEqual(text.frame.minY, header.frame.maxY)
        capture(app, "RTL-大字号文档首行不被遮挡")
        app.buttons["imessage.media.preview.close"].tap()
    }

}
