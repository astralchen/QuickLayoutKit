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
        if let tabs = sourceViewController.tabBarController as? AppTabBarController,
           let tab = AppTab(route: route) {
            tabs.select(tab)
            return
        }
        if let split = sourceViewController.splitViewController as? ExampleSplitViewController {
            split.select(route)
            return
        }
        guard let destination = makeViewController(for: route) else { return }
        destination.navigationItem.title = localizer.text(route.titleKey)
        destination.navigationItem.largeTitleDisplayMode = .never
        sourceViewController.navigationController?.pushViewController(
            destination,
            animated: true
        )
    }

    func makeViewController(for route: MainRoute) -> UIViewController? {
        switch route {
        case .horizontalScroll:
            HorizontalScrollViewViewController()
        case .safeAreaPadding:
            SafeAreaPaddingViewController()
        case .contentMargins:
            ContentMarginsViewController()
        case .positionAndZIndex:
            PositionAndZIndexViewController()
        case .viewThatFits:
            ViewThatFitsViewController()
        case .fixedSize:
            FixedSizeViewController()
        // 每次进入创建新的实验室，实验状态只保留在该控制器生命周期内。
        case .frame:
            FrameLabViewController()
        case .containerRelativeSize:
            ContainerRelativeSizeViewController()
        case .geometry:
            GeometryViewController()
        case .arrangement:
            ArrangementViewController()
        case .directionalGrid:
            DirectionalGridViewController()
        case .profile:
            ProfileViewController()
        case .counter:
            CounterViewController()
        case .dynamicScroll:
            DynamicScrollViewController()
        case .dashboard:
            DashboardViewController()
        case .voiceRoom:
            VoiceRoomViewController()
        case .chat:
            if #available(iOS 26.0, *) {
                ChatViewController()
            } else {
                nil
            }
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
            SemanticContentViewController()
        case .representable:
            ViewControllerRepresentableViewController()
        case .localizationOverview:
            LocalizationOverviewViewController()
        case .uikitLocalization:
            UIKitLocalizationShowcaseViewController()
        case .directionalNavigation:
            DirectionalNavigationViewController()
        case .semanticGesture:
            SemanticGestureViewController()
        case .swiftUIBridge:
            SwiftUILocalizationBridgeViewController()
        case .localizationBoundary:
            LocalizationBoundaryViewController()
        }
    }
}
