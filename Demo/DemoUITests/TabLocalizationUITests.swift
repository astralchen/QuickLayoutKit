import XCTest

final class TabLocalizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func tabButton(in app: XCUIApplication, id: String, title: String) -> XCUIElement {
        let identified = app.buttons.matching(identifier: "app.tab.\(id)").firstMatch
        // 系统重新配置 item 后可能不再暴露 identifier；名称仍必须匹配当前语言。
        return identified.exists ? identified : app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor func testEnglishChineseTabTitlesRoundTrip() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Chat requires iOS 26") }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)",
                                "-quicklayoutkit.demo.locale.identifier", "en-US"]
        app.launch()
        let identifiers = ["examples", "chat", "voiceRoom"]
        for (language, titles) in [
            ("简体中文", ["示例", "聊天", "语音房"]),
            ("English", ["Examples", "Chat", "Voice room"]),
            ("简体中文", ["示例", "聊天", "语音房"])
        ] {
            let menu = app.buttons.matching(identifier: "demo.language.menu").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                zip(identifiers, titles).allSatisfy { id, title in
                    let item = self.tabButton(in: app, id: id, title: title)
                    return item.exists && item.label == title
                }
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 10)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "tabs-english-chinese-\(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            XCTAssertEqual(result, .completed)
        }
    }

    @MainActor func testChatDraftAndFocusSurviveLanguageRoundTrip() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Chat requires iOS 26") }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)",
                                "-quicklayoutkit.demo.locale.identifier", "zh-Hans",
                                "-imessage-basic-history", "-chat-draft-session", UUID().uuidString]
        app.launch()
        let chat = app.buttons.matching(identifier: "app.tab.chat").firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        let editor = app.textViews["imessage.composer.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(chat.label, "聊天")
        editor.tap()
        var draft = "Language draft"
        app.typeText(draft)
        for (index, language) in ["العربية", "简体中文"].enumerated() {
            app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
            let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            let send = app.buttons["imessage.composer.send"]
            let expectedTitle = index == 0 ? "إرسال" : "发送"
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                send.label == expectedTitle && (editor.value as? String) == draft
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            let chatTitle = index == 0 ? "الدردشة" : "聊天"
            let localizedChat = tabButton(in: app, id: "chat", title: chatTitle)
            XCTAssertTrue(localizedChat.exists)
            XCTAssertEqual(localizedChat.label, chatTitle)
            XCTAssertTrue(localizedChat.isSelected)
            XCTAssertTrue(editor.isHittable)
            // 不再点击输入框；向应用发送键盘输入，验证焦点仍在原编辑器。
            app.typeText(" continued")
            draft += " continued"
            XCTAssertEqual(editor.value as? String, draft)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "chat-language-\(index)-draft-and-focus"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor func testChineseArabicChineseTabDirectionRoundTrip() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Three root tabs require iOS 26") }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)",
                                "-quicklayoutkit.demo.locale.identifier", "zh-Hans",
                                "-imessage-basic-history", "-chat-draft-session", UUID().uuidString]
        app.launch()
        let identifiers = ["examples", "chat", "voiceRoom"]
        let initialItems = identifiers.map {
            app.buttons.matching(identifier: "app.tab.\($0)").firstMatch
        }
        for item in initialItems { XCTAssertTrue(item.waitForExistence(timeout: 10)) }

        for (index, language) in ["简体中文", "简体中文", "العربية", "简体中文", "العربية", "简体中文"].enumerated() {
            if index > 0 {
                app.buttons.matching(identifier: "demo.language.menu").firstMatch.tap()
                let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
            }
            let rtl = language == "العربية"
            let titles = rtl ? ["الأمثلة", "الدردشة", "الغرفة الصوتية"] : ["示例", "聊天", "语音房"]
            func currentItems() -> [XCUIElement] {
                zip(identifiers, titles).map { tabButton(in: app, id: $0, title: $1) }
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let items = currentItems()
                return items.allSatisfy { $0.exists } && zip(items, titles).allSatisfy { $0.label == $1 }
                    && (rtl ? items[0].frame.midX > items[1].frame.midX && items[1].frame.midX > items[2].frame.midX
                        : items[0].frame.midX < items[1].frame.midX && items[1].frame.midX < items[2].frame.midX)
            }, object: app)
            let result = XCTWaiter.wait(for: [ready], timeout: 10)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "tabs-language-\(index)-\(rtl ? "rtl" : "ltr")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let items = currentItems()
            let states = items.map { item in
                item.exists
                    ? "id=\(item.identifier), exists=true, label=\(item.label.debugDescription), frame=\(item.frame), selected=\(item.isSelected)"
                    : "missing tab element"
            }.joined(separator: "\n")
            let diagnostic = XCTAttachment(string: states + "\n\n" + app.debugDescription)
            diagnostic.name = "tabs-language-\(index)-accessibility"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            XCTAssertEqual(result, .completed, states)
            XCTAssertTrue(items[0].isSelected)
            for item in items { XCTAssertTrue(item.isHittable) }
        }
        let items = zip(identifiers, ["示例", "聊天", "语音房"]).map { tabButton(in: app, id: $0, title: $1) }
        for index in [1, 2, 0] {
            items[index].tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                items[index].isSelected
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
    }
}
