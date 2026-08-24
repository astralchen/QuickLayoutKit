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
        let goal: Int
        let countText: String
        let progress: Float
        let eyebrow: String
        let headline: String
        let subtitle: String
        let progressText: String
        let goalText: String
        let unitText: String
        let controlsTitle: String
        let controlsSubtitle: String
        let incrementTitle: String
        let decrementTitle: String
        let resetTitle: String
        let statusTitle: String
        let statusMessage: String
        let canDecrement: Bool
        let canReset: Bool
    }

    typealias StateObserver = (State) -> Void

    private let localizer: DemoLocalizer
    private let goal: Int
    private var count: Int
    private var stateObserver: StateObserver?

    private(set) var state: State

    convenience init(initialCount: Int = 0, goal: Int = 8) {
        self.init(
            initialCount: initialCount,
            goal: goal,
            localizer: .live
        )
    }

    init(
        initialCount: Int = 0,
        goal: Int = 8,
        localizer: DemoLocalizer
    ) {
        self.localizer = localizer
        self.goal = max(goal, 1)
        count = max(initialCount, 0)
        state = Self.makeState(
            count: max(initialCount, 0),
            goal: max(goal, 1),
            localizer: localizer
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
        count = max(count - 1, 0)
        publishState()
    }

    func reset() {
        count = 0
        publishState()
    }

    func reloadLocalizedContent() {
        publishState()
    }

    private func publishState() {
        state = Self.makeState(
            count: count,
            goal: goal,
            localizer: localizer
        )
        stateObserver?(state)
    }

    private static func makeState(
        count: Int,
        goal: Int,
        localizer: DemoLocalizer
    ) -> State {
        let remaining = max(goal - count, 0)
        let statusTitleKey: String
        let statusMessage: String

        if count == 0 {
            statusTitleKey = "counter.status.ready.title"
            statusMessage = localizer.text("counter.status.ready.message")
        } else if count >= goal {
            statusTitleKey = "counter.status.complete.title"
            statusMessage = localizer.text("counter.status.complete.message")
        } else {
            statusTitleKey = "counter.status.progress.title"
            statusMessage = localizer.text(
                "counter.status.progress.message",
                Int64(remaining)
            )
        }

        return State(
            count: count,
            goal: goal,
            countText: String(count),
            progress: min(Float(count) / Float(goal), 1),
            eyebrow: localizer.text("counter.eyebrow"),
            headline: localizer.text("counter.headline"),
            subtitle: localizer.text("counter.subtitle"),
            progressText: localizer.text(
                "counter.progress",
                Int64(count),
                Int64(goal)
            ),
            goalText: localizer.text("counter.goal", Int64(goal)),
            unitText: localizer.text("counter.unit"),
            controlsTitle: localizer.text("counter.controls.title"),
            controlsSubtitle: localizer.text("counter.controls.subtitle"),
            incrementTitle: localizer.text("counter.increment"),
            decrementTitle: localizer.text("counter.decrement"),
            resetTitle: localizer.text("counter.reset"),
            statusTitle: localizer.text(statusTitleKey),
            statusMessage: statusMessage,
            canDecrement: count > 0,
            canReset: count > 0
        )
    }
}
