//
//  LiveRoomPreviewData.swift
//  Demo
//
//  仅供 Xcode Preview 使用，避免预览状态污染生产初始数据。
//

#if DEBUG

@MainActor
enum LiveRoomPreviewData {

    static let roomInformation = LiveRoomInformation(
        roomID: "PREVIEW-9527",
        hostDisplayName: "预览主播"
    )

    static let seats: [LiveRoomSeat] = [
        seat(
            id: 0,
            nameKey: "liveRoom.seat.host",
            avatarImageID: .host,
            symbolName: "person.crop.circle.fill",
            themeIndex: 0,
            score: 8_888
        ),
        seat(
            id: 1,
            nameKey: "liveRoom.seat.one",
            avatarImageID: .one,
            symbolName: "person.crop.circle.badge.checkmark",
            themeIndex: 1,
            score: 5_200
        ),
        seat(
            id: 2,
            nameKey: "liveRoom.seat.two",
            avatarImageID: .two,
            symbolName: "person.crop.circle.fill",
            themeIndex: 2,
            score: 3_888
        ),
        seat(
            id: 3,
            nameKey: "liveRoom.seat.three",
            avatarImageID: .three,
            symbolName: "person.crop.circle.fill",
            themeIndex: 3,
            score: 2_666,
            isMuted: true
        ),
        seat(
            id: 4,
            nameKey: "liveRoom.seat.four",
            avatarImageID: .four,
            symbolName: "person.crop.circle.badge.plus",
            themeIndex: 4,
            score: 1_888
        ),
        seat(
            id: 5,
            nameKey: "liveRoom.seat.five",
            avatarImageID: .five,
            symbolName: "person.crop.circle",
            themeIndex: 5,
            score: 1_520,
            isMuted: true
        ),
        seat(
            id: 6,
            nameKey: "liveRoom.seat.six",
            avatarImageID: .six,
            symbolName: "person.crop.circle",
            themeIndex: 6,
            score: 1_314
        ),
        seat(
            id: 7,
            nameKey: "liveRoom.seat.seven",
            avatarImageID: .seven,
            symbolName: "person.crop.circle",
            themeIndex: 7,
            score: 952
        ),
        seat(
            id: 8,
            nameKey: "liveRoom.seat.eight",
            avatarImageID: .eight,
            symbolName: "sofa.fill",
            themeIndex: 8,
            score: 520,
            isMuted: true
        ),
    ]

    /// 独立空麦 fixture，用于覆盖无人状态而不影响默认九麦头像展示。
    static let vacantSeat = seat(
        id: 5,
        nameKey: "liveRoom.seat.five",
        avatarImageID: nil,
        symbolName: "person.crop.circle",
        themeIndex: 5,
        score: 0,
        isMuted: true,
        isOccupied: false
    )

    static let gifts: [LiveRoomGift] = [
        gift(
            id: "heart",
            titleKey: "liveRoom.gift.item.heart",
            symbolName: "heart.fill",
            price: 10,
            themeIndex: 0,
            effectStyle: .trail
        ),
        gift(
            id: "rose",
            titleKey: "liveRoom.gift.item.rose",
            symbolName: "leaf.fill",
            price: 20,
            themeIndex: 1,
            effectStyle: .trail
        ),
        gift(
            id: "music",
            titleKey: "liveRoom.gift.item.music",
            symbolName: "music.note",
            price: 88,
            themeIndex: 3,
            effectStyle: .trail
        ),
        gift(
            id: "rocket",
            titleKey: "liveRoom.gift.item.rocket",
            symbolName: "paperplane.fill",
            price: 188,
            themeIndex: 5,
            effectStyle: .trail
        ),
        gift(
            id: "fireworks",
            titleKey: "liveRoom.gift.item.fireworks",
            symbolName: "sparkles",
            price: 666,
            themeIndex: 1,
            effectStyle: .burst
        ),
        gift(
            id: "castle",
            titleKey: "liveRoom.gift.item.castle",
            symbolName: "building.columns.fill",
            price: 888,
            themeIndex: 3,
            effectStyle: .burst
        ),
        gift(
            id: "galaxy",
            titleKey: "liveRoom.gift.item.galaxy",
            symbolName: "globe.asia.australia.fill",
            price: 5_200,
            themeIndex: 4,
            effectStyle: .celebration
        ),
        gift(
            id: "phoenix",
            titleKey: "liveRoom.gift.item.phoenix",
            symbolName: "flame.fill",
            price: 13_140,
            themeIndex: 0,
            effectStyle: .celebration
        ),
    ]

    static var occupiedSeats: [LiveRoomSeat] {
        seats.filter(\.isOccupied)
    }

    static let messages = [
        "小满：今晚的声音也太温柔了 ✨",
        "阿澈：坐等下一首歌 🎵",
        "直播间：欢迎来到预览专用直播间",
        "小满：预览数据不会进入生产状态",
    ]

    static let audienceMembers: [LiveRoomAudienceMember] = (0..<12).map {
        index in
        LiveRoomAudienceMember(
            id: index,
            displayName: "预览用户 \(index + 1)",
            avatarImageID: LiveRoomAvatarImageID.fixtures[
                index % LiveRoomAvatarImageID.fixtures.count
            ],
            themeIndex: index % 9,
            contributionScore: 12_800 - index * 520,
            presence: index < 3
                ? .onMicrophone(seatNumber: index + 1)
                : .listening
        )
    }

    static let audienceHeaderTitle = "当前在线"
    static let audienceHeaderSummary = "1,280 人在线"
    static let audienceHeaderSubtitle = "当前已加载的活跃用户"

    static let informationRoomTitle = "预览音乐小屋"
    static let informationRoomSubtitle = "唱歌 · 聊天 · Preview 专用数据"
    static let informationLiveStatus = "直播中"
    static let informationDetailsTitle = "房间资料"
    static let informationRoomIDTitle = "房间号"
    static let informationHostTitle = "主播"
    static let informationAudienceTitle = "在线人数"
    static let informationAudienceValue = "8,888 人在线"
    static let informationAnnouncementTitle = "直播间公告"
    static let informationAnnouncement = "预览数据不会进入生产状态。"

    static func makeRoomViewModel(
        businessMode: LiveRoomBusinessMode = .party,
        audienceSeatState: LiveRoomAudienceSeatState = .enabled,
        balance: Int = 88_888
    ) -> LiveRoomViewModel {
        let capacity = businessMode == .individual ? 5 : 9
        let snapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
            businessMode: businessMode,
            audienceSeatState: audienceSeatState,
            assignments: seats.filter { $0.position.rawValue < capacity }
        )
        return LiveRoomViewModel(
            initialGiftBalance: balance,
            stageSnapshot: snapshot,
            audienceCount: 8_888,
            audienceMembers: audienceMembers,
            roomInformation: roomInformation
        )
    }

    static func makeRoomInformationViewModel()
        -> LiveRoomInformationViewModel {
        LiveRoomInformationViewModel(
            information: roomInformation,
            audienceCount: 8_888
        )
    }

    private static func seat(
        id: Int,
        nameKey: String,
        avatarImageID: LiveRoomAvatarImageID?,
        symbolName: String,
        themeIndex: Int,
        score: Int,
        isMuted: Bool = false,
        isOccupied: Bool = true
    ) -> LiveRoomSeat {
        LiveRoomSeat(
            id: id,
            nameKey: nameKey,
            avatarImageID: avatarImageID,
            symbolName: symbolName,
            themeIndex: themeIndex,
            score: score,
            isMuted: isMuted,
            isOccupied: isOccupied
        )
    }

    private static func gift(
        id: String,
        titleKey: String,
        symbolName: String,
        price: Int,
        themeIndex: Int,
        effectStyle: LiveRoomGiftEffectStyle
    ) -> LiveRoomGift {
        LiveRoomGift(
            id: id,
            titleKey: titleKey,
            symbolName: symbolName,
            price: price,
            themeIndex: themeIndex,
            effectStyle: effectStyle
        )
    }
}

#endif
