//
//  SeatAssignment.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 麦位所属的房间；编号始终是房内 0 起始的位置。
nonisolated enum SeatRoomSide: Int, CaseIterable, Sendable {
    /// 麦位属于当前房间。
    case current
    /// 麦位属于 PK 对方房间。
    case opponent
}

/// 由所属房间和零基位置组成的唯一麦位地址。
nonisolated struct SeatAddress: Hashable, Comparable, Sendable {
    /// 麦位所属的房间；PK 双方独立编号。
    let roomSide: SeatRoomSide
    /// 麦位在所属房间中的零基位置。
    let position: SeatPosition

    /// 先按房间侧、再按零基位置比较两个麦位地址。
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.roomSide.rawValue == rhs.roomSide.rawValue
            ? lhs.position < rhs.position
            : lhs.roomSide.rawValue < rhs.roomSide.rawValue
    }
}

/// 服务端音频麦位的稳定标识。
///
/// 麦位标识不等同于布局位置；用户从一个布局切换到另一个布局时，服务端麦位
/// 可以重新绑定到新的 `SeatSlotID`。
nonisolated struct SeatID: Hashable, Sendable, RawRepresentable {
    /// 服务端音频麦位的原始标识字符串。
    let rawValue: String
}

/// 客户端布局中的语义位置标识。
///
/// Slot 使用语义名称而不是物理坐标，因此同一个 Slot 可以根据设备宽度、
/// Dynamic Type 和 RTL 方向解析为不同的实际位置。
nonisolated struct SeatSlotID: Hashable, Sendable, RawRepresentable {
    /// 客户端布局语义位置的原始标识字符串。
    let rawValue: String

    /// 本房主持麦的布局位置标识。
    static let host = Self(rawValue: "host")

    /// 返回指定 PK 房间侧和零基位置对应的布局标识。
    static func roomPK(_ side: SeatRoomSide, position: Int) -> Self {
        if side == .current { return position == 0 ? .host : .audience(position) }
        return Self(rawValue: "opponent.\(position)")
    }

    /// 返回指定零基观众麦位对应的布局标识。
    static func audience(_ index: Int) -> Self {
        Self(rawValue: "audience.\(index)")
    }
}

/// 麦位在房间协议中的零基位置。
///
/// 第一个麦位的位置为 `0`。位置用于后台快照排序和容量校验，不替代稳定的
/// `SeatID` 或布局语义 `SeatSlotID`。
nonisolated struct SeatPosition: Hashable, Comparable, Sendable, RawRepresentable {
    /// 服务端协议中的零基位置；首个麦位为 `0`。
    let rawValue: Int

    /// 按零基位置的数值比较两个麦位位置。
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 直播间用户的稳定业务标识。
nonisolated struct RoomUserID: Hashable, Sendable, RawRepresentable {
    /// 服务端用户身份的原始标识字符串。
    let rawValue: String
}

/// 服务端或 fixture 携带的头像资源标识。
///
/// Model 只保存稳定标识，不直接持有 `UIImage`；Support 层负责把标识解析为
/// Asset Catalog 图片，保证业务快照继续满足 Sendable。
nonisolated struct AvatarImageID:
    Hashable,
    Sendable,
    RawRepresentable {

    /// Asset Catalog 中的头像资源名称。
    let rawValue: String

    /// 主持麦演示用户的头像资源标识。
    static let host = Self(rawValue: "VoiceRoomAvatarHost")
    /// 第一张观众演示头像的资源标识。
    static let one = Self(rawValue: "VoiceRoomAvatarOne")
    /// 第二张观众演示头像的资源标识。
    static let two = Self(rawValue: "VoiceRoomAvatarTwo")
    /// 第三张观众演示头像的资源标识。
    static let three = Self(rawValue: "VoiceRoomAvatarThree")
    /// 第四张观众演示头像的资源标识。
    static let four = Self(rawValue: "VoiceRoomAvatarFour")
    /// 第五张观众演示头像的资源标识。
    static let five = Self(rawValue: "VoiceRoomAvatarFive")
    /// 第六张观众演示头像的资源标识。
    static let six = Self(rawValue: "VoiceRoomAvatarSix")
    /// 第七张观众演示头像的资源标识。
    static let seven = Self(rawValue: "VoiceRoomAvatarSeven")
    /// 第八张观众演示头像的资源标识。
    static let eight = Self(rawValue: "VoiceRoomAvatarEight")

    /// 用于生成确定性演示数据的头像资源列表。
    static let fixtures: [Self] = [
        .host, .one, .two, .three, .four, .five, .six, .seven, .eight,
    ]
}

/// 麦位上用户的纯业务快照。
///
/// Model 不保存 `UIImage` 或 `UIColor`；头像图片和主题色继续由 Support 层解析。
nonisolated struct SeatOccupant: Equatable, Sendable {
    /// 用户的稳定业务标识；跨布局关联应使用此标识。
    let userID: RoomUserID
    /// 用户昵称的本地化资源键。
    let nameKey: String
    /// 头像在资源目录中的标识。
    let avatarImageID: AvatarImageID?
    /// 显示图标使用的 SF Symbols 名称。
    let symbolName: String
    /// 从主题调色板选取颜色的索引。
    let themeIndex: Int
}

/// 麦位当前的音频状态。
nonisolated enum SeatAudioState: Equatable, Sendable {
    /// 麦位音频处于活动状态。
    case active
    /// 麦位已静音。
    case muted
    /// 麦位没有可用的音频状态。
    case unavailable
}

/// 服务端麦位、客户端布局 Slot 和用户之间的一次稳定绑定。
nonisolated struct SeatAssignment: Equatable, Sendable {
    /// 服务端音频麦位标识，与用户身份和布局位置相互独立。
    let seatID: SeatID
    /// 客户端布局中的稳定语义位置标识。
    let slotID: SeatSlotID
    /// 麦位在所属房间中的零基位置。
    let position: SeatPosition
    /// 当前占麦用户；空麦时为 `nil`。
    let occupant: SeatOccupant?
    /// 麦位当前的音频状态。
    let audioState: SeatAudioState
    /// 此麦位显示的积分。
    let score: Int
    /// 麦位所属的房间；PK 双方独立编号。
    let roomSide: SeatRoomSide

    /// 结合所属房间与零基位置得到的麦位地址。
    var address: SeatAddress { SeatAddress(roomSide: roomSide, position: position) }

    /// 当前占麦用户的稳定标识；空麦时为 `nil`。
    var userID: RoomUserID? { occupant?.userID }
    /// 一个布尔值，指示麦位是否有用户占用。
    var isOccupied: Bool { occupant != nil }
    /// 一个布尔值，指示音频是否非活动状态；静音和不可用均为 `true`。
    var isMuted: Bool { audioState != .active }
    /// 当前占麦用户的昵称资源键；空麦时为 `nil`。
    var occupantNameKey: String? { occupant?.nameKey }
    /// 用户昵称资源键；空麦时回退为通用可上麦文案键。
    var nameKey: String { occupantNameKey ?? "liveRoom.seat.available" }
    /// 当前用户的头像资源标识；空麦或未配置头像时为 `nil`。
    var avatarImageID: AvatarImageID? { occupant?.avatarImageID }
    /// 用户的备用图标名称；空麦时按麦位角色选择图标。
    var symbolName: String {
        occupant?.symbolName ?? SeatRole.roomSeat(at: position).emptySeatSymbolName
    }
    /// 用户主题色索引；空麦时使用零基麦位位置。
    var themeIndex: Int { occupant?.themeIndex ?? position.rawValue }

    /// 现有 Demo 测试使用的麦位序号。
    ///
    /// 业务关联必须使用强类型 ID；该属性只负责保留界面文案和测试可读性。
    var id: Int { position.rawValue }

    /// 使用服务端稳定 ID 创建麦位绑定。
    init(
        seatID: SeatID,
        slotID: SeatSlotID,
        position: SeatPosition,
        occupant: SeatOccupant?,
        audioState: SeatAudioState,
        score: Int,
        roomSide: SeatRoomSide = .current
    ) {
        self.roomSide = roomSide
        self.seatID = seatID
        self.slotID = slotID
        self.position = position
        self.occupant = occupant
        self.audioState = audioState
        self.score = max(0, score)
    }

    /// 使用 Demo fixture 创建稳定麦位绑定。
    ///
    /// 生产服务端快照应使用 `seatID`、`slotID` 和 `occupant` 初始化方法。
    init(
        id: Int,
        nameKey: String,
        avatarImageID: AvatarImageID?,
        symbolName: String,
        themeIndex: Int,
        score: Int,
        isMuted: Bool,
        isOccupied: Bool
    ) {
        roomSide = .current
        seatID = SeatID(rawValue: "seat.\(id)")
        slotID = id == 0 ? .host : .audience(id)
        position = SeatPosition(rawValue: id)
        occupant = isOccupied
            ? SeatOccupant(
                userID: RoomUserID(rawValue: "user.\(id)"),
                nameKey: nameKey,
                avatarImageID: avatarImageID,
                symbolName: symbolName,
                themeIndex: themeIndex
            )
            : nil
        audioState = isOccupied
            ? (isMuted ? .muted : .active)
            : .unavailable
        self.score = max(0, score)
    }
}
