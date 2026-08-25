//
//  MainRouter.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import UIKit

@MainActor
protocol DemoRouting: AnyObject {
    func navigate(to route: DemoRoute, from sourceViewController: UIViewController)
}

@MainActor
final class DemoRouter: DemoRouting {

    private let localizer: DemoLocalizer

    convenience init() {
        self.init(localizer: .live)
    }

    init(localizer: DemoLocalizer) {
        self.localizer = localizer
    }

    func navigate(
        to route: DemoRoute,
        from sourceViewController: UIViewController
    ) {
        let destination = makeViewController(for: route)
        destination.navigationItem.title = localizer.text(route.titleKey)
        sourceViewController.navigationController?.pushViewController(
            destination,
            animated: true
        )
    }

    private func makeViewController(for route: DemoRoute) -> UIViewController {
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
        case .messages:
            MesssageViewController()
        case .tableMessages:
            MessageTableViewController()
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
