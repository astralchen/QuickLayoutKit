import Foundation

/// 与 UIKit 无关的根功能身份；系统版本变化不会改变其他 Tab 的身份。
enum AppTab: String, CaseIterable, Sendable {
    case examples, chat, voiceRoom

    init?(route: MainRoute) {
        switch route {
        case .chat: self = .chat
        case .voiceRoom: self = .voiceRoom
        default: return nil
        }
    }

    var titleKey: String { "app.tab.\(rawValue)" }
    var symbol: String {
        switch self {
        case .examples: "square.grid.2x2"
        case .chat: "message"
        case .voiceRoom: "music.mic"
        }
    }
}

@MainActor
final class AppNavigationViewModel {
    struct State: Equatable {
        struct Item: Equatable {
            let id: AppTab
            let title: String
            let symbol: String
        }
        var items: [Item]
        var selectedTab: AppTab
    }

    private let tabs: [AppTab]
    private let localizer: Localizer
    private var stateDidChange: ((State) -> Void)?
    private(set) var state: State

    init(chatAvailable: Bool = MainRoute.chat.isAvailable, localizer: Localizer = .live) {
        self.localizer = localizer
        tabs = AppTab.allCases.filter { $0 != .chat || chatAvailable }
        state = State(items: tabs.map {
            State.Item(id: $0, title: localizer.text($0.titleKey), symbol: $0.symbol)
        }, selectedTab: .examples)
    }

    func bind(_ handler: @escaping (State) -> Void) {
        stateDidChange = handler
        handler(state)
    }

    func select(_ tab: AppTab) {
        guard tabs.contains(tab), state.selectedTab != tab else { return }
        state.selectedTab = tab
        stateDidChange?(state)
    }

    func reloadLocalizedContent() {
        state.items = tabs.map { State.Item(id: $0, title: localizer.text($0.titleKey), symbol: $0.symbol) }
        stateDidChange?(state)
    }
}

/// 详情选择独立于分栏展开状态，容器重排不会触发业务页面重建。
@MainActor
final class ExampleNavigationViewModel {
    private(set) var selectedRoute: MainRoute?

    @discardableResult
    func select(_ route: MainRoute) -> Bool {
        guard route.isAvailable, AppTab(route: route) == nil, selectedRoute != route else { return false }
        selectedRoute = route
        return true
    }
}
