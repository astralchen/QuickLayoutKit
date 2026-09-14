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

    let state: State

    init(member: AudienceMember) {
        state = State(member: member)
    }
}
