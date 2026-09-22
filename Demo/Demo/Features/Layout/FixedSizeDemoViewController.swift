import QuickLayout
import QuickLayoutKit
import UIKit

/// 协调页面导航、本地化与原文跳转；展示状态由页面视图管理。
final class FixedSizeDemoViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.fixedSize.title" }

    let contentView = FixedSizeDemoView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        contentView.onOpenSource = { [weak self] in
            guard let url = URL(string: "https://www.swiftdifferently.com/blog/swiftui/fixedsize-usecase") else { return }
            self?.viewIfLoaded?.window?.windowScene?.open(url, options: nil, completionHandler: nil)
        }
        updateNavigationAppearance()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                (controller: FixedSizeDemoViewController, _: UITraitCollection) in
                controller.updateNavigationAppearance()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) != false {
            updateNavigationAppearance()
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        contentView.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        contentView.reloadLayoutDirection(direction)
    }

    override var body: Layout {
        contentView.resizable()
    }

    private func updateNavigationAppearance() {
        // 滚动时让导航标题与彩色实验卡片分离，保持深浅色模式下的对比度。
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor.systemGroupedBackground.resolvedColor(with: traitCollection)
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label.resolvedColor(with: traitCollection)
        ]
        navigationAppearance.shadowColor = .clear
        navigationItem.standardAppearance = navigationAppearance
        navigationItem.scrollEdgeAppearance = navigationAppearance
        navigationItem.compactAppearance = navigationAppearance
        navigationItem.compactScrollEdgeAppearance = navigationAppearance
    }

}

#if DEBUG
@available(iOS 17.0, *)
@MainActor
private func makeFixedSizePreview(
    scenario: FixedSizeScenario = .equal,
    interfaceStyle: UIUserInterfaceStyle = .unspecified,
    contentSizeCategory: UIContentSizeCategory = .large,
    layoutDirection: UIUserInterfaceLayoutDirection? = nil
) -> UIViewController {
    let controller = FixedSizeDemoViewController()
    let navigationController = UINavigationController(rootViewController: controller)
    navigationController.overrideUserInterfaceStyle = interfaceStyle
    navigationController.traitOverrides.preferredContentSizeCategory = contentSizeCategory
    controller.overrideUserInterfaceStyle = interfaceStyle
    controller.traitOverrides.preferredContentSizeCategory = contentSizeCategory
    controller.loadViewIfNeeded()
    controller.contentView.selectScenario(scenario)
    if let layoutDirection {
        navigationController.view.semanticContentAttribute = layoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
        controller.reloadLayoutDirection(layoutDirection)
    }
    return navigationController
}

@available(iOS 17.0, *)
#Preview("内容等高") {
    makeFixedSizePreview()
}

@available(iOS 17.0, *)
#Preview("自然高度") {
    makeFixedSizePreview(scenario: .natural)
}

@available(iOS 17.0, *)
#Preview("撑满容器 · 420 pt") {
    makeFixedSizePreview(scenario: .fill)
}

@available(iOS 17.0, *)
#Preview("深色 · 内容等高") {
    makeFixedSizePreview(interfaceStyle: .dark)
}

@available(iOS 17.0, *)
#Preview("辅助功能大字号") {
    makeFixedSizePreview(contentSizeCategory: .accessibilityExtraExtraExtraLarge)
}

@available(iOS 17.0, *)
#Preview("RTL · 内容等高") {
    makeFixedSizePreview(layoutDirection: .rightToLeft)
}
#endif
