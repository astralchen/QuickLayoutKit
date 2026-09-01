//
//  IMessageChatViewModel.swift
//  Demo
//

import AppLocalization
import Foundation

@MainActor
final class IMessageChatViewModel {

    enum UpdateReason: Equatable {
        case initial
        case sentMessage
        case receivedMessage
        case localization
    }

    struct State: Equatable {
        let timeline: [IMessageChatTimelineItem]
        let isTyping: Bool
    }

    typealias Clock = @MainActor () -> Date
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias StateHandler = (State, UpdateReason) -> Void

    private static let timestampInterval: TimeInterval = 5 * 60

    private let localizer: DemoLocalizer
    private let clock: Clock
    private let sleeper: Sleeper
    private var render: StateHandler?
    private var messages: [IMessageChatMessage]
    private var nextMessageID: Int
    private var pendingReplyTask: Task<Void, Never>?
    private var isTyping = false

    private(set) var state: State

    convenience init() {
        self.init(
            localizer: .live,
            clock: Date.init,
            sleeper: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    init(
        localizer: DemoLocalizer,
        clock: @escaping Clock,
        sleeper: @escaping Sleeper
    ) {
        self.localizer = localizer
        self.clock = clock
        self.sleeper = sleeper

        let now = clock()
        messages = [
            IMessageChatMessage(
                id: 0,
                direction: .incoming,
                content: .localized(key: "imessage.seed.incoming.1"),
                sentAt: now.addingTimeInterval(-8 * 60),
                deliveryState: nil
            ),
            IMessageChatMessage(
                id: 1,
                direction: .outgoing,
                content: .localized(key: "imessage.seed.outgoing.1"),
                sentAt: now.addingTimeInterval(-7 * 60),
                deliveryState: .read
            ),
            IMessageChatMessage(
                id: 2,
                direction: .incoming,
                content: .localized(key: "imessage.seed.incoming.2"),
                sentAt: now.addingTimeInterval(-6 * 60),
                deliveryState: nil
            ),
        ]
        nextMessageID = 3
        state = State(timeline: [], isTyping: false)
        state = makeState()
    }

    deinit {
        pendingReplyTask?.cancel()
    }

    func bind(_ render: @escaping StateHandler) {
        self.render = render
        render(state, .initial)
    }

    /// 发送用户输入的纯文本。首尾空白不属于消息内容，内部换行保持原样。
    @discardableResult
    func send(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        pendingReplyTask?.cancel()
        messages.append(
            IMessageChatMessage(
                id: nextMessageID,
                direction: .outgoing,
                content: .userText(text),
                sentAt: clock(),
                deliveryState: .delivered
            )
        )
        nextMessageID += 1
        isTyping = true
        publish(reason: .sentMessage)
        scheduleReply()
        return true
    }

    func refreshLocalizedContent() {
        publish(reason: .localization)
    }

    func cancelPendingReply() {
        pendingReplyTask?.cancel()
        pendingReplyTask = nil
        guard isTyping else { return }
        isTyping = false
        publish(reason: .localization)
    }

    private func scheduleReply() {
        let sleeper = sleeper
        pendingReplyTask = Task { [weak self] in
            do {
                try await sleeper(.milliseconds(900))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.completeReply()
        }
    }

    private func completeReply() {
        pendingReplyTask = nil
        if let latestOutgoingIndex = messages.lastIndex(where: {
            $0.direction == .outgoing
        }) {
            messages[latestOutgoingIndex].deliveryState = .read
        }
        messages.append(
            IMessageChatMessage(
                id: nextMessageID,
                direction: .incoming,
                content: .localized(key: "imessage.reply.1"),
                sentAt: clock(),
                deliveryState: nil
            )
        )
        nextMessageID += 1
        isTyping = false
        publish(reason: .receivedMessage)
    }

    private func publish(reason: UpdateReason) {
        state = makeState()
        render?(state, reason)
    }

    private func makeState() -> State {
        var timeline: [IMessageChatTimelineItem] = []
        var previousDate: Date?
        let latestOutgoingID = messages.last(where: {
            $0.direction == .outgoing
        })?.id

        for message in messages {
            if previousDate == nil
                || message.sentAt.timeIntervalSince(previousDate!)
                    >= Self.timestampInterval {
                let timestamp = IMessageChatTimestampPresentation(
                    sourceMessageID: message.id,
                    text: Self.timestampText(
                        for: message.sentAt,
                        locale: DemoLocalization.localizationController
                            .currentLocale.locale
                    )
                )
                timeline.append(
                    IMessageChatTimelineItem(
                        id: .timestamp(sourceMessageID: message.id),
                        content: .timestamp(timestamp)
                    )
                )
            }

            let deliveryText: String?
            if message.id == latestOutgoingID,
               let deliveryState = message.deliveryState {
                deliveryText = localizer.text(
                    deliveryState == .read
                        ? "imessage.status.read"
                        : "imessage.status.delivered"
                )
            } else {
                deliveryText = nil
            }

            let presentation = IMessageChatMessagePresentation(
                id: message.id,
                direction: message.direction,
                text: resolvedText(message.content),
                deliveryText: deliveryText
            )
            timeline.append(
                IMessageChatTimelineItem(
                    id: .message(message.id),
                    content: .message(presentation)
                )
            )
            previousDate = message.sentAt
        }

        if isTyping {
            timeline.append(
                IMessageChatTimelineItem(
                    id: .typing,
                    content: .typing(
                        accessibilityLabel: localizer.text(
                            "imessage.typing.accessibility"
                        )
                    )
                )
            )
        }

        return State(timeline: timeline, isTyping: isTyping)
    }

    private func resolvedText(_ content: IMessageChatMessageContent) -> String {
        switch content {
        case .localized(let key):
            localizer.text(key)
        case .userText(let text):
            text
        }
    }

    private static func timestampText(
        for date: Date,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
