//
//  RoomInformation.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 不随本地化和在线状态变化的直播间基础资料。
struct RoomInformation: Equatable, Sendable {
    /// 房间的业务标识。
    let roomID: String
    /// 房间主播的显示名称。
    let hostDisplayName: String
}
