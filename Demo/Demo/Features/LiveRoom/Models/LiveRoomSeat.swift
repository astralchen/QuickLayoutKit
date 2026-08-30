//
//  LiveRoomSeat.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

/// 服务端音频麦位的稳定标识。
///
/// 麦位标识不等同于布局位置；用户从一个布局切换到另一个布局时，服务端麦位
/// 可以重新绑定到新的 `LiveRoomSeatSlotID`。
nonisolated struct LiveRoomSeatID: Hashable, Sendable, RawRepresentable {
    let rawValue: String
}

/// 客户端布局中的语义位置标识。
///
/// Slot 使用语义名称而不是物理坐标，因此同一个 Slot 可以根据设备宽度、
/// Dynamic Type 和 RTL 方向解析为不同的实际位置。
nonisolated struct LiveRoomSeatSlotID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    static let host = Self(rawValue: "host")

    static func audience(_ index: Int) -> Self {
        Self(rawValue: "audience.\(index)")
    }
}

/// 麦位在房间协议中的零基位置。
///
/// 第一个麦位的位置为 `0`。位置用于后台快照排序和容量校验，不替代稳定的
/// `LiveRoomSeatID` 或布局语义 `LiveRoomSeatSlotID`。
nonisolated struct LiveRoomSeatPosition: Hashable, Comparable, Sendable, RawRepresentable {
    let rawValue: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 直播间用户的稳定业务标识。
nonisolated struct LiveRoomUserID: Hashable, Sendable, RawRepresentable {
    let rawValue: String
}

/// 服务端或 fixture 携带的头像资源标识。
///
/// Model 只保存稳定标识，不直接持有 `UIImage`；Support 层负责把标识解析为
/// Asset Catalog 图片，保证业务快照继续满足 Sendable。
nonisolated struct LiveRoomAvatarImageID:
    Hashable,
    Sendable,
    RawRepresentable {

    let rawValue: String

    static let host = Self(rawValue: "LiveRoomAvatarHost")
    static let one = Self(rawValue: "LiveRoomAvatarOne")
    static let two = Self(rawValue: "LiveRoomAvatarTwo")
    static let three = Self(rawValue: "LiveRoomAvatarThree")
    static let four = Self(rawValue: "LiveRoomAvatarFour")
    static let five = Self(rawValue: "LiveRoomAvatarFive")
    static let six = Self(rawValue: "LiveRoomAvatarSix")
    static let seven = Self(rawValue: "LiveRoomAvatarSeven")
    static let eight = Self(rawValue: "LiveRoomAvatarEight")

    static let fixtures: [Self] = [
        .host, .one, .two, .three, .four, .five, .six, .seven, .eight,
    ]
}

/// 麦位上用户的纯业务快照。
///
/// Model 不保存 `UIImage` 或 `UIColor`；头像图片和主题色继续由 Support 层解析。
nonisolated struct LiveRoomSeatOccupant: Equatable, Sendable {
    let userID: LiveRoomUserID
    let nameKey: String
    let avatarImageID: LiveRoomAvatarImageID?
    let symbolName: String
    let themeIndex: Int
}

/// 麦位当前的音频状态。
nonisolated enum LiveRoomSeatAudioState: Equatable, Sendable {
    case active
    case muted
    case unavailable
}

/// 服务端麦位、客户端布局 Slot 和用户之间的一次稳定绑定。
nonisolated struct LiveRoomSeatAssignment: Equatable, Sendable {
    let seatID: LiveRoomSeatID
    let slotID: LiveRoomSeatSlotID
    let position: LiveRoomSeatPosition
    let occupant: LiveRoomSeatOccupant?
    let audioState: LiveRoomSeatAudioState
    let score: Int

    var userID: LiveRoomUserID? { occupant?.userID }
    var isOccupied: Bool { occupant != nil }
    var isMuted: Bool { audioState != .active }
    var occupantNameKey: String? { occupant?.nameKey }
    var nameKey: String { occupantNameKey ?? "liveRoom.seat.available" }
    var avatarImageID: LiveRoomAvatarImageID? { occupant?.avatarImageID }
    var symbolName: String {
        occupant?.symbolName ?? emptySeatSymbolName
    }
    var themeIndex: Int { occupant?.themeIndex ?? slotIndex }

    /// 现有 Demo 测试使用的麦位序号。
    ///
    /// 业务关联必须使用强类型 ID；该属性只负责保留界面文案和测试可读性。
    var id: Int { position.rawValue }

    private var slotIndex: Int {
        if slotID == .host { return 0 }
        return Int(slotID.rawValue.split(separator: ".").last ?? "0") ?? 0
    }

    private var emptySeatSymbolName: String {
        slotIndex == 8 ? "sofa.fill" : "person.crop.circle"
    }

    /// 使用服务端稳定 ID 创建麦位绑定。
    init(
        seatID: LiveRoomSeatID,
        slotID: LiveRoomSeatSlotID,
        position: LiveRoomSeatPosition,
        occupant: LiveRoomSeatOccupant?,
        audioState: LiveRoomSeatAudioState,
        score: Int
    ) {
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
        avatarImageID: LiveRoomAvatarImageID?,
        symbolName: String,
        themeIndex: Int,
        score: Int,
        isMuted: Bool,
        isOccupied: Bool
    ) {
        seatID = LiveRoomSeatID(rawValue: "seat.\(id)")
        slotID = id == 0 ? .host : .audience(id)
        position = LiveRoomSeatPosition(rawValue: id)
        occupant = isOccupied
            ? LiveRoomSeatOccupant(
                userID: LiveRoomUserID(rawValue: "user.\(id)"),
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

/// LiveRoom 现有调用点使用的麦位业务类型。
typealias LiveRoomSeat = LiveRoomSeatAssignment
