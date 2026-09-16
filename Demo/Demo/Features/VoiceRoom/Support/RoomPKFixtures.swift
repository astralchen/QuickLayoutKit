import Foundation

/// 双房演示数据只由 Mock / Preview 使用；View 不生成麦上用户。
nonisolated enum RoomPKFixtures {
    static var opponentAssignments: [SeatAssignment] {
        (0..<9).map { index in
            let occupied = index != 5 && index != 8
            return SeatAssignment(
                seatID: SeatID(rawValue: "opponent.seat.\(index)"),
                slotID: .roomPK(.opponent, position: index),
                position: SeatPosition(rawValue: index),
                occupant: occupied ? SeatOccupant(
                    userID: RoomUserID(rawValue: "opponent.user.\(index)"),
                    nameKey: "liveRoom.pk.user.\(index)",
                    avatarImageID: AvatarImageID.fixtures[(index + 3) % 9],
                    symbolName: "person.crop.circle.fill",
                    themeIndex: index + 2
                ) : nil,
                audioState: occupied ? (index == 3 ? .muted : .active) : .unavailable,
                score: occupied ? [5_548, 0, 98_200, 34_290, 4_567, 0, 55_435_600, 1_209_240, 0][index] : 0,
                roomSide: .opponent
            )
        }
    }
}
