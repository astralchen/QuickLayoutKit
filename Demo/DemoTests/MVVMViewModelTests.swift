//
//  MVVMViewModelTests.swift
//  DemoTests
//
//  Created by Codex on 2026/8/15.
//

import Testing
@testable import Demo

@MainActor
@Suite(.serialized)
struct MVVMViewModelTests {

    @Test func mainViewModelOwnsMenuStateAndEmitsPureRoutes() {
        let strings = MutableStrings(prefix: "first.")
        let viewModel = MainViewModel(localizer: strings.localizer)
        let routes = viewModel.state.sections.flatMap(\.routes).map(\.route)

        #expect(viewModel.state.sections.count == 3)
        #expect(routes.count == DemoRoute.allCases.count)
        #expect(Set(routes) == Set(DemoRoute.allCases))
        #expect(viewModel.state.sections[0].title == "first.main.section.quicklayout")

        var replayedState: MainViewModel.State?
        var selectedRoute: DemoRoute?
        viewModel.bind(
            stateDidChange: { replayedState = $0 },
            routeDidSelect: { selectedRoute = $0 }
        )

        #expect(replayedState == viewModel.state)
        viewModel.select(.tableMessages)
        #expect(selectedRoute == .tableMessages)

        strings.prefix = "second."
        viewModel.reloadLocalizedContent()
        #expect(viewModel.state.sections[0].title == "second.main.section.quicklayout")
        #expect(viewModel.state.sections[0].routes[0].title.hasPrefix("second."))
    }

    @Test func counterViewModelReplaysAndPreservesCountAcrossLocalization() {
        let strings = MutableStrings(prefix: "first.")
        let viewModel = CounterViewModel(
            initialCount: 2,
            localizer: strings.localizer
        )
        var renderedStates: [CounterViewModel.State] = []
        viewModel.bind { renderedStates.append($0) }

        #expect(renderedStates == [viewModel.state])
        #expect(viewModel.state.goal == 8)
        #expect(viewModel.state.progress == 0.25)
        #expect(viewModel.state.canDecrement)
        viewModel.increment()
        viewModel.increment()
        viewModel.decrement()
        #expect(viewModel.state.count == 3)
        #expect(viewModel.state.countText == "3")
        #expect(viewModel.state.progress == 0.375)
        #expect(
            viewModel.state.statusTitle
                == "first.counter.status.progress.title"
        )

        strings.prefix = "second."
        viewModel.reloadLocalizedContent()
        #expect(viewModel.state.count == 3)
        #expect(viewModel.state.incrementTitle == "second.counter.increment")
        #expect(viewModel.state.decrementTitle == "second.counter.decrement")
        #expect(viewModel.state.headline == "second.counter.headline")
        #expect(
            viewModel.state.progressText
                == "second.counter.progress: 3 | 8"
        )
    }

    @Test func counterViewModelClampsAtZeroAndPublishesGoalStates() {
        let strings = MutableStrings(prefix: "")
        let viewModel = CounterViewModel(
            initialCount: 0,
            goal: 2,
            localizer: strings.localizer
        )

        viewModel.decrement()
        #expect(viewModel.state.count == 0)
        #expect(viewModel.state.progress == 0)
        #expect(!viewModel.state.canDecrement)
        #expect(!viewModel.state.canReset)
        #expect(viewModel.state.statusTitle == "counter.status.ready.title")

        viewModel.increment()
        #expect(viewModel.state.count == 1)
        #expect(viewModel.state.progress == 0.5)
        #expect(viewModel.state.canDecrement)
        #expect(viewModel.state.statusTitle == "counter.status.progress.title")

        viewModel.increment()
        viewModel.increment()
        #expect(viewModel.state.count == 3)
        #expect(viewModel.state.progress == 1)
        #expect(viewModel.state.statusTitle == "counter.status.complete.title")

        viewModel.reset()
        #expect(viewModel.state.count == 0)
        #expect(viewModel.state.statusTitle == "counter.status.ready.title")
    }

    @Test func dynamicScrollViewModelUsesStableValueItems() {
        let strings = MutableStrings(prefix: "first.")
        let viewModel = DynamicScrollViewModel(
            initialItemCount: 10,
            localizer: strings.localizer
        )

        #expect(viewModel.state.items.map(\.id) == Array(0..<10))
        #expect(viewModel.state.items.count == 10)
        #expect(
            viewModel.state.items.first?.title
                == "first.dynamic.item.title: 1"
        )

        let insertedID = viewModel.addItem()
        #expect(insertedID == 10)
        #expect(viewModel.state.items.map(\.id) == Array(0...10))
        #expect(
            viewModel.state.items.last?.title
                == "first.dynamic.item.title: 11"
        )

        let idsBeforeLocalization = viewModel.state.items.map(\.id)
        let colorsBeforeLocalization = viewModel.state.items.map(\.color)
        strings.prefix = "second."
        viewModel.reloadLocalizedContent()
        #expect(viewModel.state.items.map(\.id) == idsBeforeLocalization)
        #expect(viewModel.state.items.map(\.color) == colorsBeforeLocalization)
        #expect(viewModel.state.addButtonTitle == "second.dynamic.addItem")
        #expect(
            viewModel.state.items.first?.title
                == "second.dynamic.item.title: 1"
        )
        #expect(
            viewModel.state.items.first?.deleteHint
                == "second.dynamic.item.deleteHint"
        )
        #expect(
            viewModel.state.items.first?.deleteButtonAccessibilityLabel
                == "second.dynamic.item.deleteButton: 1"
        )
        #expect(
            viewModel.state.items.first?.deleteAccessibilityHint
                == "second.dynamic.item.deleteAccessibilityHint"
        )
    }

    @Test func dynamicScrollViewModelRemovesItemsWithoutReusingIDs() {
        let strings = MutableStrings(prefix: "")
        let viewModel = DynamicScrollViewModel(
            initialItemCount: 4,
            localizer: strings.localizer
        )
        var renderedStates: [DynamicScrollViewModel.State] = []
        viewModel.bind { renderedStates.append($0) }

        #expect(viewModel.removeItem(id: 1))
        #expect(viewModel.state.items.map(\.id) == [0, 2, 3])
        #expect(viewModel.state.items.map(\.title) == [
            "dynamic.item.title: 1",
            "dynamic.item.title: 3",
            "dynamic.item.title: 4",
        ])
        #expect(renderedStates.count == 2)

        let stateAfterRemoval = viewModel.state
        #expect(!viewModel.removeItem(id: 99))
        #expect(viewModel.state == stateAfterRemoval)
        #expect(renderedStates.count == 2)

        #expect(viewModel.addItem() == 4)
        #expect(viewModel.state.items.map(\.id) == [0, 2, 3, 4])
        #expect(viewModel.state.items.last?.title == "dynamic.item.title: 5")
    }

    @Test func messageListViewModelSharesCollectionAndTablePresentation() {
        let strings = MutableStrings(prefix: "first.")
        let collectionViewModel = MessageListViewModel(
            configuration: .collection,
            localizer: strings.localizer
        )
        let tableViewModel = MessageListViewModel(
            configuration: .table,
            localizer: strings.localizer
        )

        #expect(collectionViewModel.state.items.count == 4)
        #expect(Set(collectionViewModel.state.items.map(\.id)).count == 4)
        #expect(collectionViewModel.state.headerTitle == nil)
        #expect(tableViewModel.state.items.count == 12)
        #expect(Set(tableViewModel.state.items.map(\.id)).count == 12)
        #expect(tableViewModel.state.headerTitle == "first.demo.tableMessages.header")
        #expect(tableViewModel.state.footerTitle == "first.demo.tableMessages.footer")

        strings.prefix = "second."
        tableViewModel.refreshLocalizedContent()
        #expect(tableViewModel.state.items[0].model.title == "second.messages.title.1")
        #expect(tableViewModel.state.headerDetail == "second.demo.tableMessages.header.detail")

        let emptyViewModel = MessageListViewModel(
            configuration: .init(repetitionCount: -1),
            localizer: strings.localizer
        )
        #expect(emptyViewModel.state.items.isEmpty)
    }

    @Test func formViewModelOwnsValuesFocusOrderAndSubmission() throws {
        let strings = MutableStrings(prefix: "localized.")
        let viewModel = FormViewModel(localizer: strings.localizer)

        #expect(viewModel.state.namePlaceholder == "localized.form.name")
        #expect(viewModel.nextField(after: .name) == .email)
        #expect(viewModel.nextField(after: .address) == .notes)
        #expect(viewModel.nextField(after: .notes) == nil)

        viewModel.update("Ada", for: .name)
        viewModel.update("ada@example.com", for: .email)
        viewModel.update("123", for: .phone)
        viewModel.update("Shenzhen", for: .address)
        viewModel.update("Hello", for: .notes)

        var submission: FormViewModel.Submission?
        viewModel.onSubmission = { submission = $0 }
        viewModel.submit()

        let result = try #require(submission)
        #expect(result.title == "localized.form.alert.title")
        #expect(result.actionTitle == "localized.common.ok")
        #expect(result.message.contains("Ada"))
        #expect(result.message.contains("ada@example.com"))
        #expect(result.message.contains("Shenzhen"))
        #expect(viewModel.values.name == "Ada")
    }

    @Test func localizationOverviewViewModelAdaptsServiceState() {
        let strings = MutableStrings(prefix: "")
        let serviceState = LocalizationServiceState()
        let service = LocalizationOverviewService(
            snapshot: { serviceState.snapshot },
            selectLanguage: { serviceState.select($0) }
        )
        let viewModel = LocalizationOverviewViewModel(
            localizer: strings.localizer,
            service: service
        )

        #expect(viewModel.state.currentLanguageText == "language.current: en-US")
        #expect(viewModel.state.directionText == "language.direction: LTR")
        #expect(viewModel.state.languages.first?.title == "language.follow.system")
        #expect(
            viewModel.state.languages.first(where: {
                $0.identifier == "en-US"
            })?.isSelected == true
        )

        viewModel.selectLanguage(identifier: "ar")
        #expect(serviceState.selections == ["ar"])
        #expect(viewModel.state.directionText == "language.direction: RTL")
        #expect(
            viewModel.state.languages.first(where: {
                $0.identifier == "ar"
            })?.isSelected == true
        )

        viewModel.selectLanguage(identifier: "unsupported")
        #expect(serviceState.selections == ["ar"])
    }
}

@MainActor
private final class MutableStrings {
    var prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    var localizer: DemoLocalizer {
        DemoLocalizer { [weak self] key, arguments in
            let prefix = self?.prefix ?? ""
            guard !arguments.isEmpty else { return prefix + key }
            let values = arguments.map { String(describing: $0) }
            return prefix + key + ": " + values.joined(separator: " | ")
        }
    }
}

@MainActor
private final class LocalizationServiceState {
    private static let languages = [
        LocalizationOverviewService.Language(
            identifier: "system",
            nativeName: "",
            localizedName: "System",
            isFollowSystemOption: true
        ),
        LocalizationOverviewService.Language(
            identifier: "en-US",
            nativeName: "English",
            localizedName: "English",
            isFollowSystemOption: false
        ),
        LocalizationOverviewService.Language(
            identifier: "zh-Hans",
            nativeName: "简体中文",
            localizedName: "Chinese",
            isFollowSystemOption: false
        ),
        LocalizationOverviewService.Language(
            identifier: "ar",
            nativeName: "العربية",
            localizedName: "Arabic",
            isFollowSystemOption: false
        ),
    ]

    private(set) var snapshot: LocalizationOverviewService.Snapshot
    private(set) var selections: [String] = []

    init() {
        snapshot = LocalizationOverviewService.Snapshot(
            currentLanguageSummary: "en-US",
            usesRightToLeftLayout: false,
            selectedIdentifier: "en-US",
            languages: Self.languages
        )
    }

    func select(_ identifier: String) {
        selections.append(identifier)
        snapshot = LocalizationOverviewService.Snapshot(
            currentLanguageSummary: identifier,
            usesRightToLeftLayout: identifier == "ar",
            selectedIdentifier: identifier,
            languages: Self.languages
        )
    }
}
