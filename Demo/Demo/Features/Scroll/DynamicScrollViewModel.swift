//
//  DynamicScrollViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation

@MainActor
final class DynamicScrollViewModel {

    enum ColorToken: Int, CaseIterable, Equatable {
        case red
        case blue
        case green
        case yellow
        case orange
        case purple
        case pink
        case indigo
        case teal
    }

    struct Item: Identifiable, Equatable {
        let id: Int
        let color: ColorToken
        let title: String
        let deleteHint: String
        let deleteButtonAccessibilityLabel: String
        let deleteAccessibilityHint: String
    }

    struct State: Equatable {
        let addButtonTitle: String
        let items: [Item]
    }

    typealias StateObserver = (State) -> Void

    private struct StoredItem: Equatable {
        let id: Int
        let color: ColorToken
    }

    private let localizer: DemoLocalizer
    private var items: [StoredItem] = []
    private var nextItemID = 0
    private var stateObserver: StateObserver?

    private(set) var state: State

    convenience init(initialItemCount: Int = 10) {
        self.init(
            initialItemCount: initialItemCount,
            localizer: .live
        )
    }

    init(
        initialItemCount: Int = 10,
        localizer: DemoLocalizer
    ) {
        self.localizer = localizer
        state = State(
            addButtonTitle: localizer.text("dynamic.addItem"),
            items: []
        )
        appendItems(count: initialItemCount)
        state = makeState()
    }

    func bind(_ observer: @escaping StateObserver) {
        stateObserver = observer
        observer(state)
    }

    @discardableResult
    func addItem() -> Item.ID {
        let item = makeItem()
        items.append(item)
        publishState()
        return item.id
    }

    @discardableResult
    func removeItem(id: Item.ID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        items.remove(at: index)
        publishState()
        return true
    }

    func reloadLocalizedContent() {
        publishState()
    }

    private func appendItems(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            items.append(makeItem())
        }
    }

    private func makeItem() -> StoredItem {
        let id = nextItemID
        nextItemID += 1

        let palette = ColorToken.allCases
        return StoredItem(
            id: id,
            color: palette[id % palette.count]
        )
    }

    private func makeState() -> State {
        State(
            addButtonTitle: localizer.text("dynamic.addItem"),
            items: items.map { item in
                Item(
                    id: item.id,
                    color: item.color,
                    title: localizer.text(
                        "dynamic.item.title",
                        item.id + 1
                    ),
                    deleteHint: localizer.text(
                        "dynamic.item.deleteHint"
                    ),
                    deleteButtonAccessibilityLabel: localizer.text(
                        "dynamic.item.deleteButton",
                        item.id + 1
                    ),
                    deleteAccessibilityHint: localizer.text(
                        "dynamic.item.deleteAccessibilityHint"
                    )
                )
            }
        )
    }

    private func publishState() {
        state = makeState()
        stateObserver?(state)
    }
}
