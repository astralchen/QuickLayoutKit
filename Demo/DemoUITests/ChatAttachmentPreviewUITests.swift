import XCTest
import UIKit

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
    @MainActor private func capture(_ app: XCUIApplication, _ name: String, screenshot: XCUIScreenshot? = nil) {
        let attachment = XCTAttachment(screenshot: screenshot ?? app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    /// 采样屏幕中央主图区域，显隐控件前后应保留同一画面，避免仅检查 AX 漏掉黑屏。
    @MainActor private func mediaSample(_ screenshot: XCUIScreenshot) -> [UInt8] {
        guard let source = screenshot.image.cgImage,
              let image = source.cropping(to: CGRect(x: CGFloat(source.width) * 0.2,
                  y: CGFloat(source.height) * 0.45, width: CGFloat(source.width) * 0.6,
                  height: CGFloat(source.height) * 0.1)) else {
            XCTFail("无法采样主图截图")
            return []
        }
        var bytes = [UInt8](repeating: 0, count: 64 * 32 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 64, height: 32,
                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        return bytes.enumerated().compactMap { $0.offset % 4 == 3 ? nil : $0.element }
    }
    @MainActor private func openMedia(_ app: XCUIApplication) {
        let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        media.tap()
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForExistence(timeout: 10))
    }
    /// 为真实视频的播放与跳转后播放提供无操作录屏区间；画面连续性需另行检查录屏。
    /// 两段等待期间不查询 AX、不截图、不拖动进度，让画面自行连续输出。
    @MainActor func testSentVideoUninterruptedPlaybackForRecording() {
        let app = chat(fixture: "resources-video", extra: ["-imessage-preview-draft"])
        let send = app.buttons["imessage.composer.send"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: send)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        send.tap()
        openMedia(app)
        let play = app.buttons["imessage.preview.play"]
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        print("VIDEO_UNTOUCHED_BEGIN \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 10)
        print("VIDEO_UNTOUCHED_END \(Date().timeIntervalSince1970)")
        XCTAssertGreaterThanOrEqual(playbackSeconds(app.sliders["imessage.preview.progress"]), 9)
        app.sliders["imessage.preview.progress"].adjust(toNormalizedSliderPosition: 0.25)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 10), .completed)
        print("VIDEO_AFTER_SEEK_BEGIN \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 6)
        print("VIDEO_AFTER_SEEK_END \(Date().timeIntervalSince1970)")
        XCTAssertGreaterThanOrEqual(playbackSeconds(app.sliders["imessage.preview.progress"]), 10)
        play.tap()
        capture(app, "视频-无操作播放与拖动后恢复")
        app.buttons["imessage.media.preview.close"].tap()
    }

    /// 滚动和缩略图切换自动播放，沉浸状态保持隐藏，并为连续画面检查提供无操作区间。
    @MainActor func testPagingToVideoAutoplaysWithoutShowingHiddenControls() {
        let app = chat(fixture: "resources-video")
        openMedia(app)
        let play = app.buttons["imessage.preview.play"]
        let initiallyPlaying = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [initiallyPlaying], timeout: 10), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.1"].isSelected)
        print("VIDEO_AUTOPLAY_BEGIN \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 8)
        print("VIDEO_AUTOPLAY_END \(Date().timeIntervalSince1970)")
        XCTAssertGreaterThanOrEqual(playbackSeconds(app.sliders["imessage.preview.progress"]), 7)
        play.tap()
        app.cells["imessage.preview.thumbnail.2"].tap()
        let nextPlaying = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPlaying], timeout: 10), .completed)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.cells["imessage.preview.thumbnail.2"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["imessage.media.preview.close"]
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(close.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let restoredPlaying = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [restoredPlaying], timeout: 5), .completed)
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.3"].isSelected)
        capture(app, "视频-翻页自动播放与沉浸恢复")
        app.buttons["imessage.media.preview.close"].tap()
    }

    /// 检查发送后各视频在不同播放时刻的主画面变化。
    @MainActor func testSentVideoActuallyRendersMovingFrames() {
        let app = chat(fixture: "resources-video", extra: ["-imessage-preview-draft"])
        let send = app.buttons["imessage.composer.send"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: send)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        send.tap()
        openMedia(app)
        for index in 0..<6 {
            if index > 0 {
                let target = app.cells["imessage.preview.thumbnail.\(index)"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                target.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: target)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            }
            let play = app.buttons["imessage.preview.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5))
            let progress = app.sliders["imessage.preview.progress"]
            let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
            XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
            let started = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                playbackSeconds(progress) >= 3
            }, object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 10), .completed)
            let firstFrame = app.screenshot()
            capture(app, "发送视频-\(index + 1)-播放三秒", screenshot: firstFrame)
            let initialTime = playbackSeconds(progress)
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                playbackSeconds(progress) >= initialTime + 3
            }, object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 10), .completed)
            let laterFrame = app.screenshot()
            capture(app, "发送视频-\(index + 1)-后续三秒", screenshot: laterFrame)
            let before = mediaSample(firstFrame), after = mediaSample(laterFrame)
            let difference = zip(before, after).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
            XCTAssertGreaterThan(difference / Double(max(1, before.count)), 2,
                "播放时间已前进三秒，但主视频区域仍是同一张画面")
        }
        app.buttons["imessage.media.preview.close"].tap()
    }
    /// 从辅助功能时间文案读取已播放秒数，等待媒体时钟而非固定休眠。
    @MainActor private func playbackSeconds(_ slider: XCUIElement) -> Int {
        let time = (slider.value as? String ?? "").components(separatedBy: "/")[0]
            .trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard time.count == 2 else { return 0 }
        return time[0] * 60 + time[1]
    }
    /// 从工程资源走真实导入和预览入口，验证图片、视频封面与 PDF 可用。
    @MainActor func testBundledResourcesPreview() {
        for fixture in ["resources", "resources-heic", "resources-video", "resources-pdf"] {
            let app = chat(fixture: fixture)
            if fixture == "resources-pdf" {
                let card = app.buttons.matching(identifier: "imessage.attachment.file.card").firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 30))
                card.tap()
                XCTAssertTrue(app.otherElements["imessage.preview.pdf"].waitForExistence(timeout: 10))
            } else if fixture == "resources-heic" {
                let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
                XCTAssertTrue(media.waitForExistence(timeout: 30))
                openMedia(app)
                XCTAssertFalse(app.cells["imessage.preview.thumbnail.1"].exists)
            } else {
                let media = app.descendants(matching: .any).matching(identifier: "imessage.media.message").firstMatch
                XCTAssertTrue(media.waitForExistence(timeout: 30))
                openMedia(app)
                let target = app.cells["imessage.preview.thumbnail.4"]
                XCTAssertTrue(target.waitForExistence(timeout: 5))
                target.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: target)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
                XCTAssertEqual(target.frame.width, 30, accuracy: 0.5)
                XCTAssertEqual(target.frame.midX, app.frame.midX, accuracy: 0.5)
                if fixture == "resources-video" {
                    let play = app.buttons["imessage.preview.play"]
                    XCTAssertTrue(play.waitForExistence(timeout: 10))
                    let slider = app.sliders["imessage.preview.progress"]
                    XCTAssertTrue(slider.waitForExistence(timeout: 5))
                    slider.adjust(toNormalizedSliderPosition: 0.5)
                    let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
                    XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
                } else {
                    let beforeScreenshot = app.screenshot()
                    capture(app, "真实资源-隐藏前", screenshot: beforeScreenshot)
                    let before = mediaSample(beforeScreenshot)
                    XCTAssertGreaterThan(before.reduce(0.0) { $0 + Double($1) } / Double(max(1, before.count)), 5)
                    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    center.tap()
                    XCTAssertTrue(app.buttons["imessage.media.preview.close"].waitForNonExistence(timeout: 5))
                    let hiddenScreenshot = app.screenshot()
                    let hidden = mediaSample(hiddenScreenshot)
                    XCTAssertEqual(before.count, hidden.count)
                    let difference = zip(before, hidden).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
                    XCTAssertLessThan(difference / Double(max(1, before.count)), 3,
                        "沉浸隐藏前后主图像素应保持一致，不能被全屏玻璃合成层遮蔽")
                    capture(app, "真实资源-沉浸隐藏", screenshot: hiddenScreenshot)
                    center.tap()
                    XCTAssertTrue(target.waitForExistence(timeout: 5))
                    XCTAssertTrue(target.isSelected)
                    let restoredScreenshot = app.screenshot()
                    let restored = mediaSample(restoredScreenshot)
                    let restoredDifference = zip(before, restored).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
                    XCTAssertLessThan(restoredDifference / Double(max(1, before.count)), 3,
                        "恢复控件后主图不能跟随布局宿主执行出现／消失动画")
                    capture(app, "真实资源-恢复控件", screenshot: restoredScreenshot)
                }
            }
            capture(app, "真实资源-\(fixture)")
            app.buttons["imessage.media.preview.close"].tap()
            app.terminate()
        }
    }
    /// 截图规格、点击、真实拖动和沉浸恢复共用用户实际入口。
    @MainActor func testThumbnailFilmstripGeometryScrubbingAndImmersion() {
        let app = chat(fixture: "stack20")
        openMedia(app)
        let first = app.cells["imessage.preview.thumbnail.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.frame.width, 30, accuracy: 0.5)
        XCTAssertEqual(first.frame.midX, app.frame.midX, accuracy: 0.5)
        let second = app.cells["imessage.preview.thumbnail.1"]
        let third = app.cells["imessage.preview.thumbnail.2"]
        XCTAssertEqual(second.frame.width, 20, accuracy: 0.5)
        XCTAssertEqual(second.frame.minX - first.frame.maxX, 13, accuracy: 0.5)
        XCTAssertEqual(third.frame.minX - second.frame.maxX, 3, accuracy: 0.5)
        capture(app, "胶片条-首项居中-透明背景")
        let fifth = app.cells["imessage.preview.thumbnail.4"]
        fifth.tap()
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: fifth)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(fifth.frame.midX, app.frame.midX, accuracy: 0.5)
        capture(app, "胶片条-中间项居中")
        let stripY = fifth.frame.midY
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.8, dy: stripY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.2, dy: stripY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        let current = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "imessage.preview.thumbnail.")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertNotEqual(current.identifier, "imessage.preview.thumbnail.4")
        XCTAssertEqual(current.frame.midX, app.frame.midX, accuracy: 0.5)
        let previousIdentifier = current.identifier
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()
        let close = app.buttons["imessage.media.preview.close"]
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        capture(app, "胶片条-沉浸隐藏")
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        left.press(forDuration: 0.1, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertFalse(close.exists)
        center.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let restored = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "imessage.preview.thumbnail.")).firstMatch
        XCTAssertTrue(restored.exists)
        XCTAssertNotEqual(restored.identifier, previousIdentifier)
        XCTAssertEqual(restored.frame.midX, app.frame.midX, accuracy: 0.5)
        capture(app, "胶片条-沉浸翻页后恢复")
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
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.1"].isSelected)
        let pages = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imessage.preview.page.")).allElementsBoundByIndex
        let centered = pages.min { abs($0.frame.midX - app.frame.midX) < abs($1.frame.midX - app.frame.midX) }
        XCTAssertNotNil(centered)
        XCTAssertEqual(centered?.frame.minX ?? -100, app.frame.minX, accuracy: 1)
        XCTAssertEqual(centered?.frame.width ?? 0, app.frame.width, accuracy: 1)
        capture(app, "自定义分页-快滑准确停第二页")
        app.cells["imessage.preview.thumbnail.0"].tap()
        end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertEqual(position.label, firstPosition)
        capture(app, "居中玻璃顶部-首项")
        more.tap()
        app.buttons["下一个附件"].tap()
        XCTAssertTrue(position.label.contains("2"))
        app.cells["imessage.preview.thumbnail.1"].tap()
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
        app.cells["imessage.preview.thumbnail.1"].tap()
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
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.1"].isHittable)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.1"].isSelected)
        app.buttons["imessage.media.preview.close"].tap()
    }
    /// 用真实触摸覆盖展开、拖动、松手收起；录屏用于检查中间形态及进度连续性。
    @MainActor func testVideoScrubberMorphAndRestore() {
        let app = chat(fixture: "resources-video")
        openMedia(app)
        let play = app.buttons["imessage.preview.play"]
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        let slider = app.sliders["imessage.preview.progress"]
        let before = slider.frame
        capture(app, "播放条-普通形态")
        print("SCRUB_MORPH_BEGIN \(Date().timeIntervalSince1970)")
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
        print("SCRUB_MORPH_END \(Date().timeIntervalSince1970)")
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["imessage.media.preview.close"].isHittable)
        XCTAssertTrue(app.buttons["imessage.preview.mute"].isHittable)
        XCTAssertEqual(slider.frame.midY, before.midY, accuracy: 0.5)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
        play.tap()
        slider.adjust(toNormalizedSliderPosition: 0.4)
        XCTAssertTrue(play.label.hasPrefix("播放"), "暂停状态下拖动，松手后应继续暂停")
        capture(app, "播放条-拖动后恢复")
        app.buttons["imessage.media.preview.close"].tap()
    }
    @MainActor func testVideoPlaysInlineAndSeeks() {
        let app = chat(fixture: "preview-video")
        openMedia(app)
        let play = app.buttons["imessage.preview.play"]
        XCTAssertTrue(play.exists)
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "暂停"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
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
        app.cells["imessage.preview.thumbnail.1"].tap()
        XCTAssertTrue(app.cells["imessage.preview.thumbnail.1"].isSelected)
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
