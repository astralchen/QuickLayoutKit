//
//  LiveRoomAvatarImageProvider.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import UIKit

@MainActor
extension LiveRoomSeat {

    var avatarImage: UIImage? {
        guard let avatarImageID else {
            return UIImage(systemName: symbolName)
        }
        return UIImage(named: avatarImageID.rawValue)
            ?? UIImage(systemName: symbolName)
    }
}

@MainActor
extension LiveRoomAudienceMember {

    var avatarImage: UIImage {
        UIImage(named: avatarImageID.rawValue)
            ?? UIImage(systemName: "person.crop.circle.fill")!
    }
}
