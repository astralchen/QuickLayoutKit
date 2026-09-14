//
//  AvatarImages.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

@MainActor
extension SeatAssignment {

    var avatarImage: UIImage? {
        guard let avatarImageID else {
            return UIImage(systemName: symbolName)
        }
        return UIImage(named: avatarImageID.rawValue)
            ?? UIImage(systemName: symbolName)
    }
}

@MainActor
extension AudienceMember {

    var avatarImage: UIImage {
        UIImage(named: avatarImageID.rawValue)
            ?? UIImage(systemName: "person.crop.circle.fill")!
    }
}
