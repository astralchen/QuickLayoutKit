//
//  MainViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import QuickLayout
import QuickLayoutKit

class MainViewController: DemoQuickLayoutHostingController {

    struct DemoRoute {
        let titleKey: String
        let viewControllerType: UIViewController.Type
    }

    struct DemoSection {
        let titleKey: String
        let routes: [DemoRoute]
    }

    override var localizedTitleKey: String? { "main.title" }

    let sections: [DemoSection] = [
        DemoSection(
            titleKey: "main.section.quicklayout",
            routes: [
                DemoRoute(titleKey: "demo.horizontalScroll.title", viewControllerType: HorizontalScrollViewViewController.self),
                DemoRoute(titleKey: "demo.profile.title", viewControllerType: ProfileViewController.self),
                DemoRoute(titleKey: "demo.counter.title", viewControllerType: CounterViewController.self),
                DemoRoute(titleKey: "demo.dynamicScroll.title", viewControllerType: DynamicScrollViewController.self),
                DemoRoute(titleKey: "demo.dashboard.title", viewControllerType: DashboardViewController.self),
                DemoRoute(titleKey: "demo.messages.title", viewControllerType: MesssageViewController.self),
                DemoRoute(titleKey: "demo.tableMessages.title", viewControllerType: MessageTableViewController.self),
                DemoRoute(titleKey: "demo.keyboard.title", viewControllerType: KeyboardHandlingViewController.self),
                DemoRoute(titleKey: "demo.form.title", viewControllerType: ScrollViewWithKeyboardViewController.self),
                DemoRoute(titleKey: "demo.semantic.title", viewControllerType: SemanticContentDemoViewController.self)
            ]
        ),
        DemoSection(
            titleKey: "main.section.hosting",
            routes: [
                DemoRoute(titleKey: "demo.representable.title", viewControllerType: ViewControllerRepresentableDemoViewController.self)
            ]
        ),
        DemoSection(
            titleKey: "main.section.localization",
            routes: [
                DemoRoute(titleKey: "demo.localizationOverview.title", viewControllerType: LocalizationOverviewViewController.self),
                DemoRoute(titleKey: "demo.uikitLocalization.title", viewControllerType: UIKitLocalizationShowcaseViewController.self),
                DemoRoute(titleKey: "demo.directionalNavigation.title", viewControllerType: DirectionalNavigationDemoViewController.self),
                DemoRoute(titleKey: "demo.semanticGesture.title", viewControllerType: SemanticGestureDemoViewController.self),
                DemoRoute(titleKey: "demo.swiftUIBridge.title", viewControllerType: SwiftUILocalizationBridgeDemoViewController.self),
                DemoRoute(titleKey: "demo.localizationBoundary.title", viewControllerType: LocalizationBoundaryDemoViewController.self)
            ]
        )
    ]

    private var sectionHeaders: [UILabel] = []
    private var routeButtonsByTitleKey: [String: UIButton] = [:]
    private var menuViews: [UIView] = []
    private var routeLookup: [Int: DemoRoute] = [:]
    let scrollView = QuickLayoutScrollView()
    private lazy var menuContentView = QuickLayoutView { [unowned self] in
        VStack(alignment: .leading, spacing: 12) {
            ForEach(self.menuViews) { view in
                self.menuElement(for: view)
            }
        }
        .layoutDirection(self.currentQuickLayoutDirection)
    }

    override var body: Layout {
        ScrollView(scrollView) {
            menuContentView
                .resizable(axis: .horizontal)
        }
        .contentMargins(.horizontal, 16)
        .contentMargins(.top, 16)
        .contentMargins(.bottom, 24)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        var tag = 0
        menuViews = []
        sectionHeaders = []
        routeButtonsByTitleKey = [:]

        for section in sections {
            let header = UILabel()
            header.font = .preferredFont(forTextStyle: .headline)
            header.textColor = .secondaryLabel
            header.accessibilityIdentifier = section.titleKey
            header.textAlignment = .natural
            header.semanticContentAttribute = .unspecified
            sectionHeaders.append(header)
            menuViews.append(header)

            for route in section.routes {
                let button = makeRouteButton(route: route, tag: tag)
                routeButtonsByTitleKey[route.titleKey] = button
                menuViews.append(button)
                tag += 1
            }
        }

        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        guard sectionHeaders.count == sections.count else { return }

        for (sectionIndex, section) in sections.enumerated() {
            sectionHeaders[sectionIndex].text = DemoLocalization.text(section.titleKey)

            for route in section.routes {
                guard let button = routeButtonsByTitleKey[route.titleKey] else { continue }
                button.configuration?.title = DemoLocalization.text(route.titleKey)
            }
        }

        menuContentView.setNeedsQuickLayout()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        menuContentView.setNeedsQuickLayout()
    }

    private func makeRouteButton(route: DemoRoute, tag: Int) -> UIButton {
            var config = UIButton.Configuration.filled()
            config.title = DemoLocalization.text(route.titleKey)
            config.baseBackgroundColor = .systemBlue.withAlphaComponent(0.1)
            config.baseForegroundColor = .systemBlue
            config.cornerStyle = .medium
            
            let button = UIButton(configuration: config)
            button.tag = tag
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            routeLookup[tag] = route
            return button
    }

    private var currentQuickLayoutDirection: LayoutDirection {
        DemoLocalization.currentUIKitDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private func menuElement(for view: UIView) -> Element {
        if view is UILabel {
            return view.frame(height: 28)
        }

        return view
            .resizable()
            .frame(height: 44)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        guard let route = routeLookup[sender.tag] else { return }
        let vc = route.viewControllerType.init()
        vc.navigationItem.title = DemoLocalization.text(route.titleKey)
        navigationController?.pushViewController(vc, animated: true)
    }
}


#Preview {
    UINavigationController(rootViewController: MainViewController())
}
