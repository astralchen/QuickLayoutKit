//
//  MessageListSupport.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

nonisolated enum MessageListSection: Hashable, Sendable {
    case messages
}

nonisolated struct MessageListItemID: Hashable, Sendable {
    let group: Int
    let message: String
}

struct MessageListItem {
    let id: MessageListItemID
    let model: MessageModel
}

enum MessageListFactory {

    static func localizedItems(
        repeating repetitionCount: Int = 1
    ) -> [MessageListItem] {
        let messages = MessageModel.localizedMockData()
        return (0..<max(0, repetitionCount)).flatMap { group in
            messages.map { message in
                MessageListItem(
                    id: MessageListItemID(
                        group: group,
                        message: message.imageName
                    ),
                    model: message
                )
            }
        }
    }
}
