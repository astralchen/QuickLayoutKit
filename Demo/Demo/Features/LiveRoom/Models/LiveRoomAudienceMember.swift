//
//  LiveRoomAudienceMember.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

struct LiveRoomAudienceMember: Equatable, Sendable, Identifiable {

    enum Presence: Equatable, Sendable {
        case onMicrophone(seatNumber: Int)
        case listening
    }

    let id: Int
    let displayName: String
    let avatarImageID: LiveRoomAvatarImageID
    let themeIndex: Int
    let contributionScore: Int
    let presence: Presence
}
