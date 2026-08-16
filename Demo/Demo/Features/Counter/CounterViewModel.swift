//
//  CounterViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation

@MainActor
final class CounterViewModel {

    struct State: Equatable {
        let count: Int
        let countText: String
        let incrementTitle: String
        let decrementTitle: String
    }

    typealias StateObserver = (State) -> Void

    private let localizer: DemoLocalizer
    private var count: Int
    private var stateObserver: StateObserver?

    private(set) var state: State

    convenience init(initialCount: Int = 0) {
        self.init(
            initialCount: initialCount,
            localizer: .live
        )
    }

    init(
        initialCount: Int = 0,
        localizer: DemoLocalizer
    ) {
        self.localizer = localizer
        count = initialCount
        state = State(
            count: initialCount,
            countText: String(initialCount),
            incrementTitle: localizer.text("counter.increment"),
            decrementTitle: localizer.text("counter.decrement")
        )
    }

    func bind(_ observer: @escaping StateObserver) {
        stateObserver = observer
        observer(state)
    }

    func increment() {
        count += 1
        publishState()
    }

    func decrement() {
        count -= 1
        publishState()
    }

    func reloadLocalizedContent() {
        publishState()
    }

    private func publishState() {
        state = State(
            count: count,
            countText: String(count),
            incrementTitle: localizer.text("counter.increment"),
            decrementTitle: localizer.text("counter.decrement")
        )
        stateObserver?(state)
    }
}
