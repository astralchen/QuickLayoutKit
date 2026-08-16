//
//  MessageListViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation

@MainActor
final class MessageListViewModel {

    struct Configuration: Equatable {
        let repetitionCount: Int
        let headerTitleKey: String?
        let headerDetailKey: String?
        let footerTitleKey: String?

        init(
            repetitionCount: Int,
            headerTitleKey: String? = nil,
            headerDetailKey: String? = nil,
            footerTitleKey: String? = nil
        ) {
            self.repetitionCount = repetitionCount
            self.headerTitleKey = headerTitleKey
            self.headerDetailKey = headerDetailKey
            self.footerTitleKey = footerTitleKey
        }

        static let collection = Configuration(repetitionCount: 1)

        static let table = Configuration(
            repetitionCount: 3,
            headerTitleKey: "demo.tableMessages.header",
            headerDetailKey: "demo.tableMessages.header.detail",
            footerTitleKey: "demo.tableMessages.footer"
        )
    }

    struct State {
        let items: [MessageListItem]
        let headerTitle: String?
        let headerDetail: String?
        let footerTitle: String?
    }

    private let configuration: Configuration
    private let localizer: DemoLocalizer
    private var render: ((State) -> Void)?

    private(set) var state: State

    init(
        configuration: Configuration,
        localizer: DemoLocalizer
    ) {
        self.configuration = configuration
        self.localizer = localizer
        state = Self.makeState(
            configuration: configuration,
            localizer: localizer
        )
    }

    convenience init(configuration: Configuration) {
        self.init(configuration: configuration, localizer: .live)
    }

    convenience init(localizer: DemoLocalizer) {
        self.init(configuration: .collection, localizer: localizer)
    }

    convenience init() {
        self.init(configuration: .collection, localizer: .live)
    }

    func bind(_ render: @escaping (State) -> Void) {
        self.render = render
        render(state)
    }

    func refreshLocalizedContent() {
        state = Self.makeState(
            configuration: configuration,
            localizer: localizer
        )
        render?(state)
    }

    private static func makeState(
        configuration: Configuration,
        localizer: DemoLocalizer
    ) -> State {
        State(
            items: MessageListFactory.localizedItems(
                repeating: configuration.repetitionCount,
                localizer: localizer
            ),
            headerTitle: localizedText(
                for: configuration.headerTitleKey,
                localizer: localizer
            ),
            headerDetail: localizedText(
                for: configuration.headerDetailKey,
                localizer: localizer
            ),
            footerTitle: localizedText(
                for: configuration.footerTitleKey,
                localizer: localizer
            )
        )
    }

    private static func localizedText(
        for key: String?,
        localizer: DemoLocalizer
    ) -> String? {
        guard let key else { return nil }
        return localizer.text(key)
    }
}
