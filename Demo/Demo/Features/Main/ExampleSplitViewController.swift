import AppLocalization
import UIKit

/// 示例目录与详情的分栏容器。
///
/// 宽窗口中目录和详情并排；窄窗口中由 UIKit 折叠成单列导航。
/// 两种呈现共用同一组控制器，切换 Tab 或折叠／展开时保留当前示例及其页面状态。
/// 这里使用 iOS 14 起提供的列式 API，可用于 Demo 的 iOS 15 部署目标。
final class ExampleSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UIKitLocalizationApplying {
    let menuController = MainViewController()
    let detailNavigationController = UINavigationController()
    let viewModel = ExampleNavigationViewModel()
    var selectedRoute: MainRoute? { viewModel.selectedRoute }
    private let factory = MainRouter()

    init() {
        // .doubleColumn 定义两列：.primary 是目录，.secondary 是详情。
        // “双列”描述容器结构，不保证屏幕上始终同时显示两列。
        super.init(style: .doubleColumn)
        // 接收折叠／展开回调，并决定折叠后的单列导航首先显示哪一列。
        delegate = self

        // 显示模式描述“哪些列可见、如何排列”：期望目录位于详情旁边。
        // preferred 是偏好；实际结果由 UIKit 根据容器空间决定，可读取 displayMode。
        preferredDisplayMode = .oneBesideSecondary
        // 分栏行为描述各列如何分配空间：.tile 让目录与详情各占一部分宽度。
        // 它与覆盖详情的 .overlay 不同；不要自行从详情宽度再次扣除目录宽度。
        preferredSplitBehavior = .tile

        // 目录期望占整个 Split 宽度的 28%，并受 260～360 pt 的最小／最大宽度约束。
        // 若以后设置 preferredPrimaryColumnWidth（绝对宽度），它会优先于比例值。
        // 这些值控制展开布局的列宽，不是窗口折叠阈值。
        minimumPrimaryColumnWidth = 260
        maximumPrimaryColumnWidth = 360
        preferredPrimaryColumnWidthFraction = 0.28

        // 按列角色安装子控制器，而不是依靠 viewControllers 数组下标。
        // 每列显式持有自己的导航栈；UIKit 负责折叠／展开时的导航呈现。
        // 列式 API 也能自动包装非导航控制器，这里显式创建以便管理导航栈。
        let menuNavigation = UINavigationController(rootViewController: menuController)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-catalog-scroll-swiftui-reference") {
            menuNavigation.setViewControllers([CatalogScrollReference.makeController()], animated: false)
        }
        #endif
        setViewController(menuNavigation, for: .primary)
        // 未选择示例时，展开的详情列也应有内容；折叠时优先显示目录。
        detailNavigationController.setViewControllers([ExamplePlaceholderController()], animated: false)
        setViewController(detailNavigationController, for: .secondary)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ route: MainRoute) {
        guard route.isAvailable, AppTab(route: route) == nil else { return }
        // 只有路由变化才替换详情，重复选择同一示例保留原控制器的状态。
        if viewModel.select(route) {
            guard let destination = factory.makeViewController(for: route) else { return }
            destination.navigationItem.largeTitleDisplayMode = .never
            detailNavigationController.setViewControllers([destination], animated: false)
        }
        menuController.selectedRoute = route
        // 折叠时把详情列带到单列导航顶部；若已经在顶部则不重复压栈。
        // 展开时 UIKit 对 show(.secondary) 不做操作，因为详情是展开布局的基准列。
        // 统一调用这个列式 API，无需根据设备型号手动 push／present。
        show(.secondary)
    }

    /// UIKit 准备折叠时询问：单列导航顶部应显示哪一列？
    /// proposedTopColumn 是系统建议；这里按业务选择覆盖：有详情就继续看详情，否则看目录。
    /// 只返回列角色，不在此重建控制器或修改路由。
    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
        selectedRoute == nil ? .primary : .secondary
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // 容器已经折叠，菜单读取实际 isCollapsed：恢复进入详情的箭头，清除侧栏选中态。
        // isCollapsed 表示列合并为单列；展开状态下暂时隐藏侧栏并不等于折叠。
        menuController.updateSplitPresentation()
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        // 容器已经展开：隐藏目录箭头，并按当前详情的路由恢复侧栏高亮。
        menuController.updateSplitPresentation()
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
