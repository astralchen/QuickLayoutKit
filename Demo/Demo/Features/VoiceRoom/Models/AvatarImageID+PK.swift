/// PK 对方使用独立的生成头像；数组位置与零基麦位位置一致。
nonisolated extension AvatarImageID {
    /// 按对方麦位位置排列的 PK 演示头像资源。
    static let pkOpponentFixtures: [Self?] = [
        Self(rawValue: "VoiceRoomPKAvatarHost"),
        Self(rawValue: "VoiceRoomPKAvatarOne"),
        Self(rawValue: "VoiceRoomPKAvatarTwo"),
        Self(rawValue: "VoiceRoomPKAvatarThree"),
        Self(rawValue: "VoiceRoomPKAvatarFour"),
        nil,
        Self(rawValue: "VoiceRoomPKAvatarSix"),
        Self(rawValue: "VoiceRoomPKAvatarSeven"),
        nil,
    ]

    /// PK 本房的九张独立头像，按零基麦位位置分配给进入 PK 时的用户。
    static let pkCurrentFixtures: [Self] = [
        Self(rawValue: "VoiceRoomPKAvatarExtra01"),
        Self(rawValue: "VoiceRoomPKAvatarExtra02"),
        Self(rawValue: "VoiceRoomPKAvatarExtra03"),
        Self(rawValue: "VoiceRoomPKAvatarExtra04"),
        Self(rawValue: "VoiceRoomPKAvatarExtra05"),
        Self(rawValue: "VoiceRoomPKAvatarExtra06"),
        Self(rawValue: "VoiceRoomPKAvatarExtra07"),
        Self(rawValue: "VoiceRoomPKAvatarExtra08"),
        Self(rawValue: "VoiceRoomPKAvatarExtra09"),
    ]
}
