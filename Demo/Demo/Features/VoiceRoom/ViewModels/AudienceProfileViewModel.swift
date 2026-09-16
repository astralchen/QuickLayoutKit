//
//  AudienceProfileViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

@MainActor
final class AudienceProfileViewModel {

    struct State: Equatable {
        let member: AudienceMember
    }

    private(set) var state: State

    init(member: AudienceMember) {
        state = State(member: member)
    }

    func update(member: AudienceMember) {
        guard member.id == state.member.id else { return }
        state = State(member: member)
    }
}
