//
//  RoomInformationViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 提供房间基础资料及在线人数的只读展示状态。
@MainActor
final class RoomInformationViewModel {

    /// 界面渲染所需的一组一致状态。
    struct State: Equatable {
        /// 房间基础资料。
        let information: RoomInformation
        /// 房间当前显示的在线人数。
        let audienceCount: Int
    }

    /// 最近一次提交的界面状态。
    let state: State

    /// 创建房间资料状态，并将负在线人数归零。
    init(information: RoomInformation, audienceCount: Int) {
        state = State(
            information: information,
            audienceCount: max(0, audienceCount)
        )
    }
}
