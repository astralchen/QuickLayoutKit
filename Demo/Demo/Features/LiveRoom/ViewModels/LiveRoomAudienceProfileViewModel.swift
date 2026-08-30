//
//  LiveRoomAudienceProfileViewModel.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

@MainActor
final class LiveRoomAudienceProfileViewModel {

    struct State: Equatable {
        let member: LiveRoomAudienceMember
    }

    let state: State

    init(member: LiveRoomAudienceMember) {
        state = State(member: member)
    }
}
