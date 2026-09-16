//
//  AudienceSheetViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

@MainActor
final class AudienceSheetViewModel {

    struct State: Equatable {
        let totalCount: Int
        let members: [AudienceMember]
    }

    private(set) var state: State

    init(totalCount: Int, members: [AudienceMember]) {
        state = Self.makeState(totalCount: totalCount, members: members)
    }

    func update(totalCount: Int, members: [AudienceMember]) {
        state = Self.makeState(totalCount: totalCount, members: members)
    }

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
