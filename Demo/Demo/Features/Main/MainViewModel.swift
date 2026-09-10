//
//  MainViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation

@MainActor
final class MainViewModel {

    struct State: Equatable {
        let sections: [Section]

        struct Section: Equatable {
            let id: String
            let title: String
            let routes: [Route]
        }

        struct Route: Equatable {
            let id: String
            let route: MainRoute
            let title: String
        }
    }

    typealias StateHandler = (State) -> Void
    typealias SelectionHandler = (MainRoute) -> Void

    private struct SectionDefinition {
        let titleKey: String
        let routes: [MainRoute]
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(
            titleKey: "main.section.quicklayout",
            routes: [
                .horizontalScroll,
                .safeAreaPadding,
                .contentMargins,
                .positionAndZIndex,
                .viewThatFits,
                .profile,
                .counter,
                .dynamicScroll,
                .dashboard,
                .liveRoom,
                .imessageChat,
                .messages,
                .tableMessages,
                .keyboard,
                .form,
                .semanticContent,
            ]
        ),
        SectionDefinition(
            titleKey: "main.section.hosting",
            routes: [
                .representable,
            ]
        ),
        SectionDefinition(
            titleKey: "main.section.localization",
            routes: [
                .localizationOverview,
                .uikitLocalization,
                .directionalNavigation,
                .semanticGesture,
                .swiftUIBridge,
                .localizationBoundary,
            ]
        ),
    ]

    private let localizer: Localizer
    private var stateHandler: StateHandler?
    private var selectionHandler: SelectionHandler?

    private(set) var state: State
    private(set) var searchQuery = ""

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: Localizer) {
        self.localizer = localizer
        state = Self.makeState(
            definitions: Self.sectionDefinitions,
            localizer: localizer
        )
    }

    /// 将视图绑定到当前状态和导航输出。
    ///
    /// 绑定后立即发送当前状态，确保基础控制器在 `viewDidLoad` 完成绑定前请求
    /// 本地化刷新时，视图仍能收到可靠的初始状态。
    func bind(
        stateDidChange: @escaping StateHandler,
        routeDidSelect: @escaping SelectionHandler
    ) {
        stateHandler = stateDidChange
        selectionHandler = routeDidSelect
        stateDidChange(state)
    }

    func reloadLocalizedContent() {
        state = Self.makeState(
            definitions: Self.sectionDefinitions,
            localizer: localizer,
            query: searchQuery
        )
        stateHandler?(state)
    }

    func updateSearchQuery(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != searchQuery else { return }
        searchQuery = query
        reloadLocalizedContent()
    }

    func select(_ route: MainRoute) {
        guard state.sections.contains(where: { section in
            section.routes.contains(where: { $0.route == route })
        }) else {
            return
        }
        selectionHandler?(route)
    }

    private static func makeState(
        definitions: [SectionDefinition],
        localizer: Localizer,
        query: String = ""
    ) -> State {
        State(
            sections: definitions.compactMap { definition in
                let section = State.Section(
                    id: definition.titleKey,
                    title: localizer.text(definition.titleKey),
                    routes: definition.routes.map { route in
                        State.Route(
                            id: route.titleKey,
                            route: route,
                            title: localizer.text(route.titleKey)
                        )
                    }
                )
                guard !query.isEmpty else { return section }
                let routes = section.routes.filter {
                    $0.title.localizedStandardContains(query)
                        || section.title.localizedStandardContains(query)
                }
                guard !routes.isEmpty else { return nil }
                return State.Section(
                    id: section.id,
                    title: section.title,
                    routes: routes
                )
            }
        )
    }
}
