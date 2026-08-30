//
//  LiveRoomInformationViewModel.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

@MainActor
final class LiveRoomInformationViewModel {

    struct State: Equatable {
        let information: LiveRoomInformation
        let audienceCount: Int
    }

    let state: State

    init(information: LiveRoomInformation, audienceCount: Int) {
        state = State(
            information: information,
            audienceCount: max(0, audienceCount)
        )
    }
}
