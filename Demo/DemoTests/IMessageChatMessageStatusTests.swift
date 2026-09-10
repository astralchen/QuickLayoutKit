import Foundation
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct IMessageChatMessageStatusTests {
    @Test func deliveryReadAndTypingAreSeparateEvents() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay)
        defer { model.cancelPendingReply() }
        #expect(model.send("hello"))
        #expect(message(model, 3)?.deliveryState == .sending)
        #expect(!model.state.isTyping && model.state.isProcessingMessages)
        #expect(await eventually { sender.calls.count == 1 })
        sender.resolve(0, success: true)
        #expect(await eventually { delay.calls.count == 1 })
        #expect(delay.calls == [.milliseconds(300)])
        #expect(message(model, 3)?.deliveryState == .delivered)
        #expect(!model.state.isTyping)
        delay.resume()
        #expect(await eventually { delay.calls.count == 2 })
        #expect(message(model, 3)?.deliveryState == .read)
        #expect(model.state.isTyping)
        #expect(message(model, 4) == nil)
        delay.resume()
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(message(model, 4)?.direction == .incoming)
        #expect(!model.state.isTyping)
    }

    @Test func failedMessagesRemainVisibleAndRetryKeepsIdentityAndRejectsDoubleTap() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay)
        defer { model.cancelPendingReply() }
        #expect(model.send("first"))
        #expect(model.send("second"))
        #expect(await eventually { sender.calls.count == 2 })
        sender.resolve(0, success: false)
        sender.resolve(1, success: false)
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(message(model, 3)?.deliveryText == "imessage.status.failed")
        #expect(message(model, 4)?.deliveryText == "imessage.status.failed")
        #expect(delay.calls.isEmpty)
        let original = try #require(sender.calls.first)
        #expect(model.retryMessage(id: 3))
        #expect(!model.retryMessage(id: 3))
        #expect(!model.retryMessage(id: 0))
        #expect(await eventually { sender.calls.count == 3 })
        #expect(sender.calls[2].id == original.id)
        #expect(sender.calls[2].content == original.content)
        #expect(sender.calls[2].sentAt == original.sentAt)
        #expect(message(model, 3)?.deliveryState == .sending)
        sender.resolve(2, success: true)
        #expect(await eventually { delay.calls.count == 1 })
        delay.resume()
        #expect(await eventually { delay.calls.count == 2 })
        delay.resume()
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(message(model, 3)?.deliveryState == .read)
        #expect(message(model, 4)?.deliveryState == .failed)
        #expect(message(model, 4)?.deliveryText == "imessage.status.failed")
        #expect(message(model, 5)?.direction == .incoming)
        #expect(message(model, 6) == nil)
    }

    @Test func receiptsAreMonotonicAndNeverReadFailedOrInFlightMessages() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay)
        defer { model.cancelPendingReply() }
        #expect(model.sendContents([.userText("one"), .userText("two"), .userText("three")]))
        #expect(await eventually { sender.calls.count == 3 })
        sender.resolve(1, success: false)
        sender.resolve(2, success: true)
        #expect(await eventually { message(model, 5)?.deliveryState == .delivered })
        #expect(delay.calls.isEmpty) // 第一条尚未送达，不能越过队列开始回复。
        model.receiveReadReceipt(through: 999)
        #expect(message(model, 5)?.deliveryState == .delivered)
        model.receiveReadReceipt(through: 5)
        #expect(message(model, 3)?.deliveryState == .sending)
        #expect(message(model, 4)?.deliveryState == .failed)
        #expect(message(model, 5)?.deliveryState == .read)
        model.receiveReadReceipt(through: 4)
        #expect(message(model, 5)?.deliveryState == .read)
        model.cancelPendingReply()
        sender.resolve(0, success: true)
        #expect(await eventually { sender.completed == 3 })
        #expect(message(model, 3)?.deliveryState == .failed)
        #expect(!model.state.isProcessingMessages)
    }

    @Test func repliesDoNotImplyReadWhenReceiptsAreDisabled() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay, receipts: false)
        defer { model.cancelPendingReply() }
        #expect(model.send("hello"))
        #expect(await eventually { sender.calls.count == 1 })
        sender.resolve(0, success: true)
        #expect(await eventually { delay.calls.count == 1 })
        delay.resume()
        #expect(await eventually { delay.calls.count == 2 })
        #expect(model.state.isTyping)
        #expect(message(model, 3)?.deliveryState == .delivered)
        delay.resume()
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(message(model, 4)?.direction == .incoming)
        #expect(message(model, 3)?.deliveryState == .delivered)
    }

    @Test func failedDelayReleasesTypingAndAllowsFollowingMessages() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay)
        defer { model.cancelPendingReply() }
        #expect(model.send("first"))
        #expect(await eventually { sender.calls.count == 1 })
        sender.resolve(0, success: true)
        #expect(await eventually { delay.calls.count == 1 })
        delay.resume()
        #expect(await eventually { delay.calls.count == 2 })
        #expect(model.state.isTyping)
        delay.resume(fails: true)
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(!model.state.isTyping)
        #expect(message(model, 3)?.deliveryState == .read)
        #expect(model.send("next"))
        #expect(await eventually { sender.calls.count == 2 })
        sender.resolve(1, success: false)
        #expect(await eventually { !model.state.isProcessingMessages })
    }

    @Test func cancelAndRetryIgnoreLateSendCompletionFromEarlierAttempt() async throws {
        let sender = StatusSender(), delay = StatusDelay()
        let model = makeModel(sender, delay)
        defer { model.cancelPendingReply() }
        #expect(model.send("first"))
        #expect(await eventually { sender.calls.count == 1 })
        model.cancelPendingReply()
        #expect(model.retryMessage(id: 3))
        #expect(await eventually { sender.calls.count == 2 })
        sender.resolve(0, success: true)
        #expect(await eventually { sender.completed == 1 })
        #expect(message(model, 3)?.deliveryState == .sending)
        sender.resolve(1, success: false)
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(message(model, 3)?.deliveryState == .failed)
        #expect(delay.calls.isEmpty)
    }

    @Test func statusViewSupportsRetryReuseRTLAndLargeText() {
        let view = IMessageChatDeliveryStatusView()
        var ids: [Int] = []
        view.retryRequested = { ids.append($0) }
        let failed = IMessageChatMessagePresentation(id: 7, direction: .outgoing, text: "x",
                                                     deliveryText: "尚未送达", deliveryState: .failed)
        view.configure(failed)
        let size = view.sizeThatFits(.init(width: 180, height: 100))
        #expect(size.width >= 44 && size.height >= 44)
        view.frame = .init(origin: .zero, size: size)
        view.semanticContentAttribute = .forceRightToLeft
        view.layoutIfNeeded()
        #expect(view.label.frame.minX == 0)
        #expect(view.accessibilityTraits.contains(.button))
        view.sendActions(for: .touchUpInside)
        #expect(ids == [7])
        let sending = IMessageChatMessagePresentation(id: 8, direction: .outgoing, text: "x",
                                                      deliveryText: "发送中…", deliveryState: .sending)
        view.configure(sending)
        view.sendActions(for: .touchUpInside)
        #expect(ids == [7] && view.progress.isAnimating)
        view.label.font = .systemFont(ofSize: 34)
        #expect(view.sizeThatFits(.init(width: 100, height: 300)).height > 44)
        view.configure(nil)
        view.sendActions(for: .touchUpInside)
        #expect(ids == [7] && !view.progress.isAnimating)
        #expect(view.accessibilityHint == nil)
        #expect(sending.refreshIdentity != IMessageChatMessagePresentation(id: 8, direction: .outgoing,
            text: "x", deliveryText: "发送中…", deliveryState: .failed).refreshIdentity)
    }

    @Test func rapidStatusRendersRefreshVisibleCellsAndRemovePreviousReceipt() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIViewController()
        let conversation = IMessageConversationView(frame: window.bounds)
        host.view = conversation
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        func state(oldText: String?, status: IMessageChatDeliveryState?, text: String?, incoming: Bool = false) -> IMessageChatViewModel.State {
            var rows = [IMessageChatTimelineItem(id: .message(1), content: .message(.init(
                id: 1, direction: .outgoing, text: "old", deliveryText: oldText, deliveryState: .read)))]
            if let status {
                rows.append(.init(id: .message(3), content: .message(.init(
                    id: 3, direction: .outgoing, text: "new", deliveryText: text, deliveryState: status))))
            }
            if incoming { rows.append(.init(id: .message(4), content: .message(.init(
                id: 4, direction: .incoming, text: "reply", deliveryText: nil)))) }
            return .init(timeline: rows, isTyping: false)
        }
        func labels() -> [String] {
            conversation.collectionView.layoutIfNeeded()
            return conversation.collectionView.visibleCells.compactMap { ($0 as? IMessageBubbleCell)?.deliveryLabel.text }.sorted()
        }
        conversation.render(state(oldText: "old read", status: nil, text: nil), reason: .initial)
        #expect(await eventually { labels() == ["old read"] })
        conversation.render(state(oldText: nil, status: .sending, text: "sending"), reason: .sentMessage)
        conversation.render(state(oldText: nil, status: .failed, text: "failed"), reason: .messageStatus)
        conversation.render(state(oldText: nil, status: .sending, text: "sending"), reason: .messageStatus)
        conversation.render(state(oldText: nil, status: .delivered, text: "delivered"), reason: .messageStatus)
        conversation.render(state(oldText: nil, status: .read, text: "read"), reason: .messageStatus)
        conversation.render(state(oldText: nil, status: .read, text: "read", incoming: true), reason: .receivedMessage)
        conversation.render(state(oldText: nil, status: .read, text: "read", incoming: true), reason: .messageStatus)
        #expect(await eventually { labels() == ["read"] })
        #expect(conversation.collectionView.visibleCells.compactMap { $0 as? IMessageBubbleCell }.allSatisfy {
            !$0.deliveryStatusView.progress.isAnimating && !$0.deliveryStatusView.isUserInteractionEnabled
        })
    }

    private func makeModel(_ sender: StatusSender, _ delay: StatusDelay, receipts: Bool = true) -> IMessageChatViewModel {
        IMessageChatViewModel(localizer: Localizer { key, _ in key }, clock: Date.init,
                             messageSender: sender, readReceiptsEnabled: receipts, sleeper: { try await delay.sleep($0) })
    }
    private func message(_ model: IMessageChatViewModel, _ id: Int) -> IMessageChatMessagePresentation? {
        model.state.timeline.compactMap { if case .message(let message) = $0.content { message } else { nil } }
            .first { $0.id == id }
    }
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

@MainActor
private final class StatusSender: IMessageChatMessageSending {
    var calls: [IMessageChatMessage] = []
    var completed = 0
    private var waits: [Int: CheckedContinuation<Void, Error>] = [:]
    func send(_ message: IMessageChatMessage) async throws {
        let index = calls.count
        calls.append(message)
        defer { completed += 1 }
        try await withCheckedThrowingContinuation { waits[index] = $0 }
    }
    func resolve(_ index: Int, success: Bool) {
        if success { waits.removeValue(forKey: index)?.resume() }
        else { waits.removeValue(forKey: index)?.resume(throwing: CocoaError(.fileWriteUnknown)) }
    }
}

@MainActor
private final class StatusDelay {
    var calls: [Duration] = []
    private var waits: [CheckedContinuation<Void, Error>] = []
    func sleep(_ duration: Duration) async throws {
        calls.append(duration)
        try await withCheckedThrowingContinuation { waits.append($0) }
    }
    func resume(fails: Bool = false) {
        let wait = waits.removeFirst()
        if fails { wait.resume(throwing: CocoaError(.userCancelled)) } else { wait.resume() }
    }
}
