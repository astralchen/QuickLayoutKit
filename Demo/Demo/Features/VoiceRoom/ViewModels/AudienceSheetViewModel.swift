//
//  AudienceSheetViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 维护去重、排序后的观众列表和在线人数。
@MainActor
final class AudienceSheetViewModel {

    /// 界面渲染所需的一组一致状态。
    struct State: Equatable {
        /// 在线总人数，不小于已加载的观众数量。
        let totalCount: Int
        /// 按展示顺序排列的观众列表。
        let members: [AudienceMember]
    }

    /// 最近一次提交的界面状态。
    private(set) var state: State

    /// 使用在线人数和观众列表创建去重、排序后的初始状态。
    init(totalCount: Int, members: [AudienceMember]) {
        state = Self.makeState(totalCount: totalCount, members: members)
    }

    /// 重新去重和排序观众列表，并更新在线总人数。
    func update(totalCount: Int, members: [AudienceMember]) {
        state = Self.makeState(totalCount: totalCount, members: members)
    }

    /// 按用户标识去重后，依次按在麦状态、贡献值和用户标识生成稳定顺序。
    private static func makeState(totalCount: Int, members: [AudienceMember]) -> State {
        var memberIDs = Set<RoomUserID>()
        // 服务端分页合并可能产生重复用户；展示层只接收稳定、去重后的快照。
        let uniqueMembers = members.filter { memberIDs.insert($0.id).inserted }
        let sortedMembers = uniqueMembers.sorted { lhs, rhs in
            switch (lhs.presence, rhs.presence) {
            case (.onMicrophone, .listening):
                return true
            case (.listening, .onMicrophone):
                return false
            default:
                if lhs.contributionScore != rhs.contributionScore {
                    return lhs.contributionScore > rhs.contributionScore
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }
        }
        return State(
            // 总人数不能小于当前已经加载出来的用户数。
            totalCount: max(max(0, totalCount), sortedMembers.count),
            members: sortedMembers
        )
    }
}
