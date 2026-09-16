//
//  AudienceMember.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 观众列表中一个用户的身份、贡献值和在麦状态。
struct AudienceMember: Equatable, Sendable, Identifiable {

    /// 观众在当前房间中的参与状态。
    enum Presence: Equatable, Sendable {
        /// 用户占用本房的指定麦位地址。
        case onMicrophone(address: SeatAddress)
        /// 用户在观众席收听，未占用本房麦位。
        case listening
    }

    /// 用于区分当前数据项的稳定标识。
    let id: RoomUserID
    /// 界面显示的用户昵称。
    let displayName: String
    /// 头像在资源目录中的标识。
    let avatarImageID: AvatarImageID
    /// 从主题调色板选取颜色的索引。
    let themeIndex: Int
    /// 用户在房间中的贡献积分。
    let contributionScore: Int
    /// 由当前麦位快照解析的用户参与状态。
    let presence: Presence

    /// 在麦状态只来自本房快照，观众资料不维护另一份麦位事实。
    func resolvingPresence(in assignments: [SeatAssignment]) -> Self {
        let address = assignments.first {
            $0.roomSide == .current && $0.userID == id
        }?.address
        return Self(
            id: id,
            displayName: displayName,
            avatarImageID: avatarImageID,
            themeIndex: themeIndex,
            contributionScore: contributionScore,
            presence: address.map { .onMicrophone(address: $0) } ?? .listening
        )
    }
}
