import AppLocalization
import UIKit

/// One selected example survives tab changes and split collapse/expansion.
final class DemoSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UIKitLocalizationApplying {
    let menuController = MainViewController()
    let detailNavigationController = UINavigationController()
    let viewModel = ExampleNavigationViewModel()
    var selectedRoute: MainRoute? { viewModel.selectedRoute }
    private let factory = MainRouter()

    init() {
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        minimumPrimaryColumnWidth = 260
        maximumPrimaryColumnWidth = 360
        preferredPrimaryColumnWidthFraction = 0.28
        let menuNavigation = UINavigationController(rootViewController: menuController)
        setViewController(menuNavigation, for: .primary)
        detailNavigationController.setViewControllers([ExamplePlaceholderController()], animated: false)
        setViewController(detailNavigationController, for: .secondary)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ route: MainRoute) {
        guard route.isAvailable, AppTab(route: route) == nil else { return }
        if viewModel.select(route) {
            guard let destination = factory.makeViewController(for: route) else { return }
            destination.navigationItem.largeTitleDisplayMode = .never
            detailNavigationController.setViewControllers([destination], animated: false)
        }
        menuController.selectedRoute = route
        show(.secondary)
    }

    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
        selectedRoute == nil ? .primary : .secondary
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        menuController.updateSelectedRoute()
    }

    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        view.semanticContentAttribute = update.semanticContentAttribute
        if #available(iOS 17.0, *) { traitOverrides.layoutDirection = update.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight }
    }
}

private final class ExamplePlaceholderController: LocalizedViewController {
    private let message = UILabel()
    override var localizedTitleKey: String? { "app.tab.examples" }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        message.font = .preferredFont(forTextStyle: .title3)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textAlignment = .center
        message.textColor = .secondaryLabel
        message.accessibilityIdentifier = "examples.placeholder"
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: 540)
        ])
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        message.text = Localization.text("app.examples.select")
    }
}
