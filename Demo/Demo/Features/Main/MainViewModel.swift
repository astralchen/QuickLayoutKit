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
            let route: DemoRoute
            let title: String
        }
    }

    typealias StateHandler = (State) -> Void
    typealias SelectionHandler = (DemoRoute) -> Void

    private struct SectionDefinition {
        let titleKey: String
        let routes: [DemoRoute]
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

    private let localizer: DemoLocalizer
    private var stateHandler: StateHandler?
    private var selectionHandler: SelectionHandler?

    private(set) var state: State

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: DemoLocalizer) {
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
            localizer: localizer
        )
        stateHandler?(state)
    }

    func select(_ route: DemoRoute) {
        guard state.sections.contains(where: { section in
            section.routes.contains(where: { $0.route == route })
        }) else {
            return
        }
        selectionHandler?(route)
    }

    private static func makeState(
        definitions: [SectionDefinition],
        localizer: DemoLocalizer
    ) -> State {
        State(
            sections: definitions.map { definition in
                State.Section(
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
            }
        )
    }
}
