import Foundation

/// Demo 的确定性公屏事件，与 View 和舞台布局无关。
enum RoomPublicChatFixtures {
    static let messages: [RoomPublicMessage] = {
        let host = RoomPublicMessage.Author(
            id: RoomUserID(rawValue: "host.user"),
            name: .localized("liveRoom.user.host"), role: .host
        )
        let guest = RoomPublicMessage.Author(
            id: RoomUserID(rawValue: "party.user.1"),
            name: .localized("liveRoom.user.party.1")
        )
        let listener = RoomPublicMessage.Author(
            id: RoomUserID(rawValue: "party.user.2"),
            name: .localized("liveRoom.user.party.2")
        )
        return [
            .init(id: "welcome", content: .system(.localized("liveRoom.publicChat.welcome"))),
            .init(id: "host.welcome", content: .text(author: host, body: .localized("liveRoom.publicChat.hostWelcome"))),
            .init(id: "guest.arrival", content: .arrival(guest)),
            .init(id: "guest.song", content: .text(author: guest, body: .localized("liveRoom.publicChat.song"))),
            .init(id: "listener.arrival", content: .arrival(listener)),
            .init(id: "listener.hello", content: .text(author: listener, body: .localized("liveRoom.publicChat.hello"))),
            .init(id: "guest.gift", content: .gift(author: guest, recipients: [host], gift: Gift.catalog[0], quantity: 10)),
            .init(id: "host.thanks", content: .text(author: host, body: .localized("liveRoom.publicChat.thanks"))),
        ]
    }()
}
