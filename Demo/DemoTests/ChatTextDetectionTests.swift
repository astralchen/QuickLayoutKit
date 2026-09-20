import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: ChatTestAvailability.isSupported))
struct ChatTextDetectionTests {
    @Test(arguments: ["en", "zh-Hans", "ar"])
    func localizedSamplesKeepAllElevenPairsInOrder(language: String) async throws {
        guard #available(iOS 26.0, *) else { return }
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let localizer = Localizer { key, _ in bundle.localizedString(forKey: key, value: nil, table: nil) }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let history = try await SampleChatHistory.load(store: store, localizer: localizer)
        let names = ["plain", "phone", "address", "url", "email", "date", "flight", "shipment", "money", "physicalValue", "mixed"]
        #expect(history.count == 38)
        for (index, name) in names.enumerated() {
            let key = "imessage.seed.text.\(name)"
            let expected = localizer.text(key)
            #expect(!expected.isEmpty && expected != key)
            #expect(history[index * 2].direction == .incoming)
            #expect(history[index * 2 + 1].direction == .outgoing)
            #expect(history[index * 2].content == .userText(expected))
            #expect(history[index * 2 + 1].content == .userText(expected))
        }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.date.rawValue)
        let text = names.map { localizer.text("imessage.seed.text.\($0)") }.joined(separator: "\n")
        let results = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        #expect(results.contains { $0.resultType == .phoneNumber })
        #expect(results.contains { $0.resultType == .address })
        #expect(results.contains { $0.url?.scheme == "https" })
        #expect(results.contains { $0.url?.scheme == "mailto" })
        // Foundation 检测语言受当前系统环境影响；英语样例验证日期匹配，其余语言保留系统判定。
        if language == "en" { #expect(results.contains { $0.resultType == .date }) }
        #expect(localizer.text("imessage.seed.text.phone").contains("+86"))
        #expect(localizer.text("imessage.seed.text.address").contains("北京市"))
    }

    @Test func detectorTextFitsBubbleAndClearsOnReuse() throws {
        guard #available(iOS 16.0, *) else { return }
        let message = "电话 +1 (202) 555-0147\n1 Apple Park Way, Cupertino, CA 95014\nhttps://www.apple.com\nhello@example.com\ntomorrow at 3:30 PM\nUA123\n1Z999AA10123456784\nUS$25.00\n10 km; 72 °F"
        for direction in [MessageDirection.incoming, .outgoing] {
            for rtl in [false, true] {
                let bubble = BubbleView(frame: .zero)
                bubble.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                bubble.configure(.init(id: 0, direction: direction, text: message, deliveryText: nil))
                let view = bubble.messageTextView
                #expect(!view.isEditable && view.isSelectable && !view.isScrollEnabled)
                #expect(view.dataDetectorTypes == [.phoneNumber, .link, .address, .calendarEvent,
                    .flightNumber, .shipmentTrackingNumber, .money, .physicalValue])
                #expect(!view.dataDetectorTypes.contains(.lookupSuggestion))
                #expect(view.linkTextAttributes[.foregroundColor] as? UIColor == (direction == .outgoing ? .white : .link))
                let wide = bubble.sizeThatFits(CGSize(width: 280, height: 1000))
                let narrow = bubble.sizeThatFits(CGSize(width: 140, height: 1000))
                #expect(wide.width <= 280 && wide.height > 50)
                #expect(narrow.width <= 140 && narrow.height >= wide.height)
                bubble.configure(.init(id: 1, direction: direction, text: "OK", deliveryText: nil))
                #expect(bubble.sizeThatFits(CGSize(width: 280, height: 1000)).width < 100)
                #expect(view.text == "OK")
                var links = 0
                view.attributedText.enumerateAttribute(.link, in: NSRange(location: 0, length: view.attributedText.length)) { value, _, _ in
                    if value != nil { links += 1 }
                }
                #expect(links == 0)
                bubble.reset()
                #expect(view.text.isEmpty && view.accessibilityLabel == nil)
            }
        }
    }

    @Test(arguments: ["en", "zh-Hans", "ar"])
    func localizedDetectedBubblesRenderInBothDirections(language: String) async throws {
        guard #available(iOS 26.0, *) else { return }
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let history = try await SampleChatHistory.load(store: store,
            localizer: Localizer { key, _ in bundle.localizedString(forKey: key, value: nil, table: nil) })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let model = ChatViewModel()
        let controller = ChatViewController(viewModel: model)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { model.cancelPendingReply(); window.isHidden = true; previous?.makeKey() }
        model.insertInitialHistory(Array(history[16..<20]))
        try await Task.sleep(for: .milliseconds(600))
        controller.conversationView.applyLayoutDirection(language == "ar" ? .rightToLeft : .leftToRight)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        let cells = controller.conversationView.collectionView.visibleCells.compactMap { $0 as? BubbleCell }
        #expect(cells.count == 4)
        for cell in cells {
            let body = cell.bubbleView.messageTextView
            let center = body.convert(CGPoint(x: body.bounds.midX, y: body.bounds.midY), to: window)
            let hit = window.hitTest(center, with: nil)
            #expect(hit === body || hit?.isDescendant(of: body) == true, "Body hit intercepted by \(String(describing: hit))")
        }
        let capture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try capture.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("detected-bubbles-\(language).png"))
        #expect(model.messages.count == 4)
        #expect(model.sendTasks.isEmpty)
    }

    @Test func detectionKeepsRichTextStylesAtAccessibilitySizes() async throws {
        guard #available(iOS 26.0, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let bubble = BubbleView(frame: .zero)
        root.view.addSubview(bubble)
        let text = MessageText(runs: [.init("https://www.apple.com", style: .bold),
            .init("\nUS$25.00 · 10 km", style: [.italic, .underline]), .init("\nOld price", style: .strikethrough)])
        bubble.configure(.init(id: 1, direction: .incoming, richText: text, deliveryText: nil))
        let regularHeight = bubble.sizeThatFits(CGSize(width: 280, height: 2000)).height
        bubble.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        try await Task.sleep(for: .milliseconds(200))
        bubble.frame = CGRect(origin: CGPoint(x: 20, y: 100),
                              size: bubble.sizeThatFits(CGSize(width: 280, height: 2000)))
        bubble.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(bubble.sizeThatFits(CGSize(width: 280, height: 2000)).height > regularHeight)
        #expect(MessageText(attributedString: bubble.messageTextView.attributedText) == text)
        #expect(bubble.messageTextView.linkTextAttributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        let capture = UIGraphicsImageRenderer(bounds: bubble.bounds).image { _ in
            UIColor.systemBackground.setFill()
            UIBezierPath(rect: bubble.bounds).fill()
            bubble.drawHierarchy(in: bubble.bounds, afterScreenUpdates: true)
        }
        try capture.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("detected-rich-accessibility.png"))
    }
}
