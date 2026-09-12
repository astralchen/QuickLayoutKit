//
//  MainRouter.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit

@MainActor
protocol MainRouting: AnyObject {
    func navigate(to route: MainRoute, from sourceViewController: UIViewController)
}

@MainActor
final class MainRouter: MainRouting {

    private let localizer: Localizer

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: Localizer) {
        self.localizer = localizer
    }

    func navigate(
        to route: MainRoute,
        from sourceViewController: UIViewController
    ) {
        let destination = makeViewController(for: route)
        destination.navigationItem.title = localizer.text(route.titleKey)
        destination.navigationItem.largeTitleDisplayMode = .never
        sourceViewController.navigationController?.pushViewController(
            destination,
            animated: true
        )
    }

    private func makeViewController(for route: MainRoute) -> UIViewController {
        switch route {
        case .horizontalScroll:
            HorizontalScrollViewViewController()
        case .safeAreaPadding:
            SafeAreaPaddingDemoViewController()
        case .contentMargins:
            ContentMarginsDemoViewController()
        case .positionAndZIndex:
            PositionAndZIndexDemoViewController()
        case .viewThatFits:
            ViewThatFitsDemoViewController()
        case .profile:
            ProfileViewController()
        case .counter:
            CounterViewController()
        case .dynamicScroll:
            DynamicScrollViewController()
        case .dashboard:
            DashboardViewController()
        case .liveRoom:
            LiveRoomViewController()
        case .imessageChat:
            IMessageChatViewController()
        case .collectionContentConfiguration:
            ContentConfigurationCollectionViewController()
        case .waterfallContentConfiguration:
            ContentConfigurationWaterfallViewController()
        case .tableContentConfiguration:
            ContentConfigurationTableViewController()
        case .keyboard:
            KeyboardHandlingViewController()
        case .form:
            ScrollViewWithKeyboardViewController()
        case .semanticContent:
            SemanticContentDemoViewController()
        case .representable:
            ViewControllerRepresentableDemoViewController()
        case .localizationOverview:
            LocalizationOverviewViewController()
        case .uikitLocalization:
            UIKitLocalizationShowcaseViewController()
        case .directionalNavigation:
            DirectionalNavigationDemoViewController()
        case .semanticGesture:
            SemanticGestureDemoViewController()
        case .swiftUIBridge:
            SwiftUILocalizationBridgeDemoViewController()
        case .localizationBoundary:
            LocalizationBoundaryDemoViewController()
        }
    }
}
