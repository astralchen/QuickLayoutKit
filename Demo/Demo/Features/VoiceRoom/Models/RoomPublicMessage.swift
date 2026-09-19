import Foundation

/// 公屏业务数据；身份及原文独立于当前语言和单元格的生命周期。
struct RoomPublicMessage: Identifiable, Equatable, Sendable {
    enum Text: Equatable, Sendable {
        case literal(String)
        case localized(String)
    }

    struct Author: Equatable, Sendable {
        enum Role: String, Equatable, Sendable { case host }
        let id: RoomUserID
        let name: Text
        var role: Role? = nil

        static let me = Author(
            id: RoomUserID(rawValue: "publicChat.localUser"),
            name: .localized("liveRoom.publicChat.me")
        )
    }

    enum Content: Equatable, Sendable {
        case text(author: Author, body: Text)
        case system(Text)
        case arrival(Author)
        /// quantity 是每名收礼人的数量，recipients 保存交易确认时的姓名快照。
        case gift(author: Author, recipients: [Author], gift: Gift, quantity: Int)
    }

    let id: String
    let content: Content

    init(id: String = UUID().uuidString, content: Content) {
        self.id = id
        self.content = content
    }
}
