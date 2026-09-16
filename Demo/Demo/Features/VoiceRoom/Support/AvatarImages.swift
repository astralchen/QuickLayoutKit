//
//  AvatarImages.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

@MainActor
extension SeatAssignment {

    /// 用户头像或角色对应的备用图标；资源解析失败时可为 `nil`。
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

    /// 观众头像；资源缺失时使用人物图标回退。
    var avatarImage: UIImage {
        UIImage(named: avatarImageID.rawValue)
            ?? UIImage(systemName: "person.crop.circle.fill")!
    }
}
