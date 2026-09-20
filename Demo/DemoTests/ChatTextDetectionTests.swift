import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: ChatTestAvailability.isSupported))
struct ChatTextDetectionTests {
    @Test func sampleTextContainsDetectableContactDetailsInBothDirections() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let history = try await SampleChatHistory.load(store: store)
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue | NSTextCheckingResult.CheckingType.link.rawValue)
        for direction in [MessageDirection.incoming, .outgoing] {
            let texts = history.filter { $0.direction == direction }.compactMap { entry -> String? in
                if case .userText(let text) = entry.content { return text }
                return nil
            }
            #expect(texts.count == 5)
            let text = texts.joined(separator: "\n")
            let results = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            #expect(results.contains { $0.resultType == .phoneNumber })
            #expect(results.contains { $0.resultType == .address })
            #expect(results.contains { $0.url?.scheme == "https" })
            #expect(results.contains { $0.url?.scheme == "mailto" })
        }
    }

    @Test func detectorTextFitsBubbleAndClearsOnReuse() throws {
        let message = "电话 +1 (202) 555-0147\n1 Apple Park Way, Cupertino, CA 95014\nhttps://www.apple.com\nhello@example.com"
        for direction in [MessageDirection.incoming, .outgoing] {
            let bubble = BubbleView(frame: .zero)
            bubble.configure(.init(id: 0, direction: direction, text: message, deliveryText: nil))
            let view = bubble.messageTextView
            #expect(!view.isEditable && view.isSelectable && !view.isScrollEnabled)
            #expect(view.dataDetectorTypes == [.phoneNumber, .link, .address])
            #expect(view.linkTextAttributes[.foregroundColor] as? UIColor == (direction == .outgoing ? .white : .link))
            let wide = bubble.sizeThatFits(CGSize(width: 280, height: 1000))
            let narrow = bubble.sizeThatFits(CGSize(width: 140, height: 1000))
            #expect(wide.width <= 280 && wide.height > 50)
            #expect(narrow.width <= 140 && narrow.height >= wide.height)
            bubble.configure(.init(id: 1, direction: direction, text: "OK", deliveryText: nil))
            #expect(bubble.sizeThatFits(CGSize(width: 280, height: 1000)).width < 100)
            #expect(view.text == "OK")
            bubble.reset()
            #expect(view.text.isEmpty && view.accessibilityLabel == nil)
        }
    }
}
