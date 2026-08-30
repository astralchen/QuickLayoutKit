//
//  LiveRoomInformation.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

/// 不随本地化和在线状态变化的直播间基础资料。
struct LiveRoomInformation: Equatable, Sendable {
    let roomID: String
    let hostDisplayName: String
}
