import AppLocalization
import UIKit

/// 临时切离功能不销毁页面拥有的草稿和附件。
@MainActor
protocol AppTabActivity: AnyObject {
    func resignActiveTab()
}

final class AppTabBarController: UITabBarController, UITabBarControllerDelegate, UIKitLocalizationApplying {
    let viewModel: AppNavigationViewModel
    private(set) var featureControllers: [AppTab: UIViewController] = [:]

    init(viewModel: AppNavigationViewModel = AppNavigationViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        // 示例 Split 拥有唯一的目录侧边栏，避免再叠加全局功能侧边栏。
        if #available(iOS 18.0, *) { mode = .tabBar }
        featureControllers[.examples] = DemoSplitViewController()
        if #available(iOS 26.0, *), viewModel.state.items.contains(where: { $0.id == .chat }) {
            featureControllers[.chat] = FeatureNavigationController { ChatViewController() }
        }
        featureControllers[.voiceRoom] = FeatureNavigationController { VoiceRoomViewController() }
        // 在 UIKit 首次创建 Tab 布局前提供完整内容，避免空项目的布局缓存。
        for item in viewModel.state.items {
            let tabItem = UITabBarItem(title: item.title, image: UIImage(systemName: item.symbol), selectedImage: nil)
            tabItem.accessibilityIdentifier = "app.tab.\(item.id.rawValue)"
            featureControllers[item.id]?.tabBarItem = tabItem
        }
        viewControllers = viewModel.state.items.compactMap { featureControllers[$0.id] }
        viewModel.bind { [weak self] state in self?.render(state) }
        applyLocalization(.initial(snapshot: Localization.localizationController.currentSnapshot))
    }

    var selectedFeature: AppTab { viewModel.state.selectedTab }

    func select(_ tab: AppTab) {
        loadViewIfNeeded()
        viewModel.select(tab)
    }

    private func render(_ state: AppNavigationViewModel.State) {
        for item in state.items {
            guard let controller = featureControllers[item.id] else { continue }
            if controller.tabBarItem.title != item.title {
                controller.tabBarItem.title = item.title
            }
        }
        guard let destination = featureControllers[state.selectedTab],
              selectedViewController !== destination else { return }
        deactivateSelectedFeature()
        selectedViewController = destination
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard featureControllers.values.contains(where: { $0 === viewController }) else { return false }
        if selectedViewController !== viewController {
            deactivateSelectedFeature()
        }
        // 用户点击交给 UIKit 完成选择，保留原生选中态及重复点击行为。
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let tab = featureControllers.first(where: { $0.value === viewController })?.key else { return }
        // UIKit 提交选择后同步状态；render 识别同一控制器，不重复切换或清理。
        viewModel.select(tab)
    }

    private func deactivateSelectedFeature() {
        guard let selected = selectedViewController else { return }
        selected.viewIfLoaded?.endEditing(true)
        let controllers = (selected as? UINavigationController)?.viewControllers ?? [selected]
        controllers.forEach { ($0 as? AppTabActivity)?.resignActiveTab() }
    }

    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        view.semanticContentAttribute = update.semanticContentAttribute
        tabBar.semanticContentAttribute = update.semanticContentAttribute
        if #available(iOS 17.0, *) { traitOverrides.layoutDirection = update.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight }
        viewModel.reloadLocalizedContent()
    }
}

/// 昂贵功能仅在第一次显示导航视图时创建；切换 Tab 保留同一实例。
final class FeatureNavigationController: UINavigationController {
    private var rootFactory: (() -> UIViewController)?

    init(rootFactory: @escaping () -> UIViewController) {
        self.rootFactory = rootFactory
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let factory = rootFactory {
            rootFactory = nil
            setViewControllers([factory()], animated: false)
        }
    }
}
