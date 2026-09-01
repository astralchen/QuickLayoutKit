//
//  IMessageChatModel.swift
//  Demo
//
//  iMessage 风格单聊演示的内部展示模型。
//

import Foundation

nonisolated enum IMessageChatDirection: String, Equatable, Hashable, Sendable {
    case incoming
    case outgoing
}

nonisolated enum IMessageChatDeliveryState: String, Equatable, Hashable, Sendable {
    case delivered
    case read
}

nonisolated enum IMessageChatMessageContent: Equatable, Hashable, Sendable {
    case localized(key: String)
    case userText(String)
}

nonisolated struct IMessageChatMessage: Equatable, Hashable, Sendable {
    let id: Int
    let direction: IMessageChatDirection
    let content: IMessageChatMessageContent
    let sentAt: Date
    var deliveryState: IMessageChatDeliveryState?
}

nonisolated struct IMessageChatMessagePresentation: Equatable, Sendable {
    let id: Int
    let direction: IMessageChatDirection
    let text: String
    let deliveryText: String?
}

nonisolated struct IMessageChatTimestampPresentation: Equatable, Sendable {
    let sourceMessageID: Int
    let text: String
}

nonisolated enum IMessageChatTimelineItemID: Hashable, Sendable {
    case timestamp(sourceMessageID: Int)
    case message(Int)
    case typing
}

nonisolated enum IMessageChatTimelineContent: Equatable, Sendable {
    case timestamp(IMessageChatTimestampPresentation)
    case message(IMessageChatMessagePresentation)
    case typing(accessibilityLabel: String)
}

nonisolated struct IMessageChatTimelineItem: Equatable, Sendable {
    let id: IMessageChatTimelineItemID
    let content: IMessageChatTimelineContent
}

