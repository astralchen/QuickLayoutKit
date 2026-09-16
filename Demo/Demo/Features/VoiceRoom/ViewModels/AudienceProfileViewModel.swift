//
//  AudienceProfileViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 持有单个观众资料页的可渲染状态。
@MainActor
final class AudienceProfileViewModel {

    /// 界面渲染所需的一组一致状态。
    struct State: Equatable {
        /// 资料页当前显示的观众。
        let member: AudienceMember
    }

    /// 最近一次提交的界面状态。
    private(set) var state: State

    /// 使用指定观众资料创建初始展示状态。
    init(member: AudienceMember) {
        state = State(member: member)
    }

    /// 用最新的观众资料替换当前展示状态。
    func update(member: AudienceMember) {
        guard member.id == state.member.id else { return }
        state = State(member: member)
    }
}
