//
//  AudienceMember.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

struct AudienceMember: Equatable, Sendable, Identifiable {

    enum Presence: Equatable, Sendable {
        case onMicrophone(address: SeatAddress)
        case listening
    }

    let id: RoomUserID
    let displayName: String
    let avatarImageID: AvatarImageID
    let themeIndex: Int
    let contributionScore: Int
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
