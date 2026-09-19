import AppLocalization
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    @Test func publicChatCommitsTextAndGiftsOnlyAfterValidation() throws {
        let model = VoiceRoomViewModel(initialGiftBalance: 1_000, publicMessages: [])
        #expect(!model.sendPublicMessage(" \n "))
        #expect(model.state.publicMessages.isEmpty)
        #expect(model.sendPublicMessage(" 同一条消息 🎵 "))
        #expect(model.sendPublicMessage("同一条消息 🎵"))
        #expect(Set(model.state.publicMessages.map(\.id)).count == 2)
        #expect(model.sentPublicMessages == ["同一条消息 🎵", "同一条消息 🎵"])
        let recipients = Array(model.state.visibleRecipients.prefix(2))
        let gift = try #require(Gift.catalog.first)
        #expect(model.processGiftSendRequest(.init(gift: gift, recipients: recipients, quantity: 10, totalCost: 200)) == 800)
        #expect(model.state.publicMessages.count == 3)
        guard case let .gift(_, names, actualGift, quantity) = model.state.publicMessages.last?.content else {
            Issue.record("成功送礼应产生一条结构化消息")
            return
        }
        #expect(names.map(\.id) == recipients.compactMap(\.userID))
        #expect(quantity == 10)
        #expect(actualGift.id == gift.id)
        #expect(model.processGiftSendRequest(.init(gift: gift, recipients: recipients, quantity: 10, totalCost: 199)) == nil)
        #expect(model.processGiftSendRequest(.init(gift: gift, recipients: [recipients[0], recipients[0]], quantity: 10, totalCost: 200)) == nil)
        #expect(model.processGiftSendRequest(.init(gift: gift, recipients: recipients, quantity: 520, totalCost: 10_400)) == nil)
        #expect(model.state.publicMessages.count == 3)
        #expect(model.giftBalance == 800)
    }

    @Test func publicChatPresentationLocalizesWithoutChangingMessageIdentity() {
        defer { Localization.setLocale(identifier: "en-US") }
        let messages = RoomPublicChatFixtures.messages
        Localization.setLocale(identifier: "zh-Hans")
        let chinese = messages.map(RoomPublicMessagePresentation.init)
        #expect(chinese.contains { $0.style == .system })
        #expect(chinese.contains { $0.style == .arrival })
        #expect(chinese.contains { $0.style == .gift })
        #expect(chinese[1].badge == "房主")
        #expect(chinese[3].badge == nil)
        Localization.setLocale(identifier: "ar")
        let arabic = messages.map(RoomPublicMessagePresentation.init)
        #expect(chinese.map(\.id) == arabic.map(\.id))
        #expect(chinese.map(\.text) != arabic.map(\.text))
        #expect(arabic.allSatisfy { !$0.text.contains("{") })
    }

    @Test func publicChatPreservesReadingPositionAndCountsOnlyNewIDs() async throws {
        let host = UIViewController()
        let chat = RoomPublicChatView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        host.view.addSubview(chat)
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        var messages = makePublicChatMessages(count: 100)
        chat.configure(messages: messages, scrollToLatest: false)
        try await settlePublicChat(chat)
        #expect(abs(chat.scrollView.contentOffset.y - publicChatBottom(chat)) < 1)
        #expect(chat.collectionView.visibleCells.count < 30)

        chat.scrollViewWillBeginDragging(chat.scrollView)
        chat.scrollView.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        chat.collectionView.layoutIfNeeded()
        chat.scrollViewDidEndDragging(chat.scrollView, willDecelerate: false)
        let index = try #require(chat.collectionView.indexPathsForVisibleItems.sorted().first)
        let frame = try #require(chat.collectionView.layoutAttributesForItem(at: index)?.frame)
        let oldRelativeY = frame.minY - chat.scrollView.contentOffset.y
        messages += makePublicChatMessages(count: 1, start: 100)
        chat.configure(messages: messages, scrollToLatest: false)
        messages += makePublicChatMessages(count: 1, start: 101)
        chat.configure(messages: messages, scrollToLatest: false)
        try await settlePublicChat(chat)
        #expect(chat.unreadMessageCount == 2)
        let newFrame = try #require(chat.collectionView.layoutAttributesForItem(at: index)?.frame)
        #expect(abs(newFrame.minY - chat.scrollView.contentOffset.y - oldRelativeY) < 1)
        chat.configure(messages: messages, scrollToLatest: false)
        #expect(chat.unreadMessageCount == 2)

        chat.frame.size = CGSize(width: 390, height: 190)
        try await settlePublicChat(chat)
        let resized = try #require(chat.collectionView.layoutAttributesForItem(at: index)?.frame)
        #expect(abs(resized.minY - chat.scrollView.contentOffset.y - oldRelativeY) < 1)
        chat.showLatestMessages()
        try await settlePublicChat(chat)
        #expect(chat.unreadMessageCount == 0)
        #expect(abs(chat.scrollView.contentOffset.y - publicChatBottom(chat)) < 1)
        messages += makePublicChatMessages(count: 1, start: 102)
        chat.configure(messages: messages, scrollToLatest: false)
        try await settlePublicChat(chat)
        #expect(abs(chat.scrollView.contentOffset.y - publicChatBottom(chat)) < 1)
        chat.scrollViewWillBeginDragging(chat.scrollView)
        chat.scrollView.setContentOffset(.zero, animated: false)
        chat.collectionView.layoutIfNeeded()
        chat.scrollViewDidEndDragging(chat.scrollView, willDecelerate: false)
        messages += makePublicChatMessages(count: 1, start: 103)
        chat.configure(messages: messages, scrollToLatest: true)
        chat.frame.size.height = 280
        try await settlePublicChat(chat)
        #expect(abs(chat.scrollView.contentOffset.y - publicChatBottom(chat)) < 1)
        #expect(chat.unreadMessageCount == 0)

        // 手指仍在拖动时到达的消息不能被迟到布局拉走，也不能丢失新消息提示。
        chat.scrollViewWillBeginDragging(chat.scrollView)
        chat.scrollViewDidScroll(chat.scrollView)
        let draggingOffset = chat.scrollView.contentOffset.y
        messages += makePublicChatMessages(count: 3, start: 104)
        chat.configure(messages: messages, scrollToLatest: false)
        try await settlePublicChat(chat)
        #expect(abs(chat.scrollView.contentOffset.y - draggingOffset) < 1)
        #expect(chat.unreadMessageCount == 3)
        chat.scrollViewDidEndDragging(chat.scrollView, willDecelerate: false)
        try await settlePublicChat(chat)
        #expect(chat.unreadMessageCount == 3)
        chat.showLatestMessages()
        try await settlePublicChat(chat)
        #expect(chat.unreadMessageCount == 0)
        #expect(abs(chat.scrollView.contentOffset.y - publicChatBottom(chat)) < 1)
    }

    @Test func publicChatEmptyShortAndLongMessagesFitAvailableWidth() async throws {
        let host = UIViewController()
        let chat = RoomPublicChatView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        host.view.addSubview(chat)
        let window = try makeVisibleTestWindow(rootViewController: host)
        defer { window.isHidden = true }
        chat.configure(messages: [], scrollToLatest: false)
        try await settlePublicChat(chat)
        #expect(chat.latestMessage == nil)
        #expect(chat.scrollView.contentOffset.y.isFinite)
        chat.configure(messages: makePublicChatMessages(count: 1), scrollToLatest: false)
        try await settlePublicChat(chat)
        let index = IndexPath(item: 0, section: 0)
        let frame = try #require(chat.collectionView.layoutAttributesForItem(at: index)?.frame)
        #expect(abs(frame.maxY - chat.scrollView.contentOffset.y - chat.bounds.height + 4) < 2)
        let long = RoomPublicMessage(content: .text(
            author: .init(id: .init(rawValue: "long"), name: .literal(String(repeating: "很长的昵称", count: 10))),
            body: .literal(String(repeating: "长消息 🎵 ", count: 90))
        ))
        chat.configure(messages: [.init(message: long)], scrollToLatest: true)
        try await settlePublicChat(chat)
        let cell = try #require(chat.collectionView.cellForItem(at: index))
        let label = try #require(cell.allSubviews(of: UILabel.self).first)
        #expect(label.bounds.width <= chat.bounds.width)
        #expect(label.bounds.height > 400)
        let fitted = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
        #expect(label.bounds.height >= fitted.height - 1)
        #expect(label.accessibilityLabel?.contains("长消息 🎵") == true)
    }

    @Test(arguments: ["zh-Hans", "ar"])
    func publicChatAdaptsToNarrowLargeTypeAndRTL(locale: String) async throws {
        Localization.setLocale(identifier: locale)
        defer { Localization.setLocale(identifier: "en-US") }
        let parent = UIViewController()
        let room = VoiceRoomViewController()
        parent.addChild(room)
        parent.view.addSubview(room.view)
        room.didMove(toParent: parent)
        parent.setOverrideTraitCollection(
            UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
            forChild: room
        )
        let window = try makeVisibleTestWindow(rootViewController: parent, size: CGSize(width: 320, height: 852))
        defer { window.isHidden = true }
        room.view.frame = parent.view.bounds
        room.view.setNeedsLayout()
        room.view.layoutIfNeeded()
        try await settlePublicChat(room.messagesView)
        let follow = try #require(room.roomHeaderView.allSubviews(of: FollowButton.self).first)
        let followFrame = follow.convert(follow.bounds, to: room.view)
        let audience = try #require(room.roomHeaderView.allSubviews(of: UIView.self).first {
            $0.accessibilityIdentifier == "liveRoom.audience.button"
        })
        let audienceFrame = audience.convert(audience.bounds, to: room.view)
        #expect(!followFrame.intersects(audienceFrame))
        #expect(audienceFrame.minX >= 0)
        #expect(audienceFrame.maxX <= room.view.bounds.width)
        #expect(!room.messagesView.collectionView.visibleCells.isEmpty)
        #expect(room.messagesView.bounds.width <= room.view.bounds.width)
        #expect(followFrame.minX >= 0)
        #expect(followFrame.maxX <= room.view.bounds.width)
        #expect(room.messagesView.collectionView.effectiveUserInterfaceLayoutDirection == (locale == "ar" ? .rightToLeft : .leftToRight))
        for cell in room.messagesView.collectionView.visibleCells {
            let label = try #require(cell.allSubviews(of: UILabel.self).first)
            #expect(label.bounds.width <= room.messagesView.bounds.width)
            #expect(label.font.pointSize > 14)
            let paragraph = label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(paragraph?.alignment == (locale == "ar" ? .right : .left))
        }
    }

    private func makePublicChatMessages(count: Int, start: Int = 0) -> [RoomPublicMessagePresentation] {
        (start..<(start + count)).map {
            .init(message: .init(id: "test.\($0)", content: .text(author: .me, body: .literal("消息 \($0) · Hello 🎵"))))
        }
    }

    private func publicChatBottom(_ chat: RoomPublicChatView) -> CGFloat {
        max(-chat.scrollView.contentInset.top,
            chat.scrollView.contentSize.height - chat.scrollView.bounds.height + chat.scrollView.contentInset.bottom)
    }
}

@MainActor
func settlePublicChat(_ chat: RoomPublicChatView) async throws {
    for _ in 0..<100 {
        chat.setNeedsLayout()
        chat.layoutIfNeeded()
        chat.commitPendingScrollToLatest()
        try await Task.sleep(for: .milliseconds(20))
        if !chat.isApplyingMessages { break }
    }
    // 自适应高度可能在 diff completion 的下一次 UIKit 布局中提交。
    for _ in 0..<5 {
        chat.setNeedsLayout()
        chat.layoutIfNeeded()
        chat.commitPendingScrollToLatest()
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!chat.isApplyingMessages)
}
