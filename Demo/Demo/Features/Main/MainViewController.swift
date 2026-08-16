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

    override var localizedTitleKey: String? { "main.title" }

    private let viewModel: MainViewModel
    private let router: any DemoRouting
    private var sectionHeadersByID: [String: UILabel] = [:]
    private var routeButtons: [DemoRoute: UIButton] = [:]
    private var menuViews: [UIView] = []
    private var routeLookup: [Int: DemoRoute] = [:]
    private var menuStructure: [(id: String, routes: [DemoRoute])] = []

    let scrollView = QuickLayoutScrollView()

    private lazy var menuContentView = QuickLayoutView { [unowned self] in
        VStack(alignment: .leading, spacing: 12) {
            ForEach(self.menuViews) { view in
                self.menuElement(for: view)
            }
        }
    }

    convenience init() {
        self.init(
            viewModel: MainViewModel(),
            router: DemoRouter()
        )
    }

    init(
        viewModel: MainViewModel,
        router: any DemoRouting
    ) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = MainViewModel()
        router = DemoRouter()
        super.init(coder: coder)
    }

    override var body: Layout {
        ScrollView(scrollView) {
            menuContentView
                .resizable(axis: .horizontal)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.top, 16)
        .contentMargins(.bottom, 24)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        bindViewModel()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)

        let semanticContentAttribute = view.semanticContentAttribute
        scrollView.semanticContentAttribute = semanticContentAttribute
        menuContentView.semanticContentAttribute = semanticContentAttribute
        routeButtons.values.forEach { button in
            button.semanticContentAttribute = semanticContentAttribute
            button.configuration = button.configuration
            button.setNeedsLayout()
        }

        menuContentView.setNeedsQuickLayout()
        scrollView.setNeedsLayout()
        setNeedsQuickLayout()
    }

    private func bindViewModel() {
        viewModel.bind(
            stateDidChange: { [weak self] state in
                self?.render(state)
            },
            routeDidSelect: { [weak self] route in
                guard let self else { return }
                self.router.navigate(to: route, from: self)
            }
        )
    }

    private func render(_ state: MainViewModel.State) {
        let newStructure = state.sections.map { section in
            (id: section.id, routes: section.routes.map(\.route))
        }

        if !hasSameMenuStructure(as: newStructure) {
            rebuildMenu(with: state)
        }

        for section in state.sections {
            sectionHeadersByID[section.id]?.text = section.title
            for routeState in section.routes {
                guard let button = routeButtons[routeState.route],
                      var configuration = button.configuration else {
                    continue
                }
                configuration.title = routeState.title
                button.configuration = configuration
            }
        }

        menuContentView.setNeedsQuickLayout()
    }

    private func rebuildMenu(with state: MainViewModel.State) {
        var tag = 0
        menuViews = []
        sectionHeadersByID = [:]
        routeButtons = [:]
        routeLookup = [:]

        for section in state.sections {
            let header = makeSectionHeader(id: section.id)
            sectionHeadersByID[section.id] = header
            menuViews.append(header)

            for routeState in section.routes {
                let button = makeRouteButton(
                    route: routeState.route,
                    title: routeState.title,
                    tag: tag
                )
                routeButtons[routeState.route] = button
                menuViews.append(button)
                tag += 1
            }
        }

        menuStructure = state.sections.map { section in
            (id: section.id, routes: section.routes.map(\.route))
        }
    }

    private func makeSectionHeader(id: String) -> UILabel {
        let header = UILabel()
        header.font = .preferredFont(forTextStyle: .headline)
        header.textColor = .secondaryLabel
        header.accessibilityIdentifier = id
        header.textAlignment = .natural
        header.semanticContentAttribute = .unspecified
        return header
    }

    private func makeRouteButton(
        route: DemoRoute,
        title: String,
        tag: Int
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = .systemBlue.withAlphaComponent(0.1)
        config.baseForegroundColor = .systemBlue
        config.cornerStyle = .medium

        let button = UIButton(configuration: config)
        button.semanticContentAttribute = scrollView.semanticContentAttribute
        button.tag = tag
        button.addTarget(
            self,
            action: #selector(buttonTapped(_:)),
            for: .touchUpInside
        )
        routeLookup[tag] = route
        return button
    }

    private func hasSameMenuStructure(
        as structure: [(id: String, routes: [DemoRoute])]
    ) -> Bool {
        guard menuStructure.count == structure.count else { return false }
        return zip(menuStructure, structure).allSatisfy { current, new in
            current.id == new.id && current.routes == new.routes
        }
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
        viewModel.select(route)
    }
}


#Preview {
    UINavigationController(rootViewController: MainViewController())
}
