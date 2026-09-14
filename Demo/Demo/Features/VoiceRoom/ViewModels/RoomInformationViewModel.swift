//
//  RoomInformationViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

@MainActor
final class RoomInformationViewModel {

    struct State: Equatable {
        let information: RoomInformation
        let audienceCount: Int
    }

    let state: State

    init(information: RoomInformation, audienceCount: Int) {
        state = State(
            information: information,
            audienceCount: max(0, audienceCount)
        )
    }
}
