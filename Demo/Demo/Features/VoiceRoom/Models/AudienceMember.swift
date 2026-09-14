//
//  AudienceMember.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

struct AudienceMember: Equatable, Sendable, Identifiable {

    enum Presence: Equatable, Sendable {
        case onMicrophone(seatNumber: Int)
        case listening
    }

    let id: Int
    let displayName: String
    let avatarImageID: AvatarImageID
    let themeIndex: Int
    let contributionScore: Int
    let presence: Presence
}
