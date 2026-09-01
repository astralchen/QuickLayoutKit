//
//  IMessageChatPreviewData.swift
//  Demo
//

#if DEBUG
import Foundation

@MainActor
enum IMessageChatPreviewData {

    static let timestamp = IMessageChatTimestampPresentation(
        sourceMessageID: 0,
        text: "19:09"
    )

    static let incomingMessage = IMessageChatMessagePresentation(
        id: 0,
        direction: .incoming,
        text: "嗨！我们今天还是按原计划见面吗？",
        deliveryText: nil
    )

    static let outgoingMessage = IMessageChatMessagePresentation(
        id: 1,
        direction: .outgoing,
        text: "当然，七点我没问题。",
        deliveryText: "已读"
    )

    static let followUpMessage = IMessageChatMessagePresentation(
        id: 2,
        direction: .incoming,
        text: "太好了，我会提前几分钟到。",
        deliveryText: nil
    )

    static let typingAccessibilityLabel = "Alex 正在输入"
    static let contactSubtitle = "iMessage"
    static let composerPlaceholder = "iMessage"
    static let sendAccessibilityLabel = "发送"
    static let composerMultilineText = "今晚七点见\n我会提前几分钟到"
    static let composerRTLText = "مساء الخير\nسأصل في السابعة"
    static let fixedDate = Date(timeIntervalSince1970: 1_788_257_740)

    static let state = IMessageChatViewModel.State(
        timeline: [
            IMessageChatTimelineItem(
                id: .timestamp(sourceMessageID: timestamp.sourceMessageID),
                content: .timestamp(timestamp)
            ),
            IMessageChatTimelineItem(
                id: .message(incomingMessage.id),
                content: .message(incomingMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(outgoingMessage.id),
                content: .message(outgoingMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(followUpMessage.id),
                content: .message(followUpMessage)
            ),
            IMessageChatTimelineItem(
                id: .typing,
                content: .typing(
                    accessibilityLabel: typingAccessibilityLabel
                )
            ),
        ],
        isTyping: true
    )
}
#endif
