import Foundation

/// 双房演示数据只由 Mock / Preview 使用；View 不生成麦上用户。
nonisolated enum RoomPKFixtures {
    /// 只在 Mock 进入 PK 时分配头像，后续快照继续携带用户头像，不由 View 补造。
    static func currentAssignments(from assignments: [SeatAssignment]) -> [SeatAssignment] {
        assignments.map { assignment in
            guard assignment.roomSide == .current,
                let occupant = assignment.occupant,
                AvatarImageID.pkCurrentFixtures.indices.contains(assignment.position.rawValue)
            else { return assignment }
            return SeatAssignment(
                seatID: assignment.seatID,
                slotID: assignment.slotID,
                position: assignment.position,
                occupant: SeatOccupant(
                    userID: occupant.userID,
                    nameKey: occupant.nameKey,
                    avatarImageID: AvatarImageID.pkCurrentFixtures[assignment.position.rawValue],
                    symbolName: occupant.symbolName,
                    themeIndex: occupant.themeIndex
                ),
                audioState: assignment.audioState,
                score: assignment.score,
                roomSide: assignment.roomSide
            )
        }
    }

    /// 使用独立用户身份和头像资源生成的对方九麦演示阵容。
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
                    avatarImageID: AvatarImageID.pkOpponentFixtures[index],
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
