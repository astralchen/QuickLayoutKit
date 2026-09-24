import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 实验室的展示模式；原始值同时对应顶部切换项和页面数组的顺序。
enum FrameLabPresentation: Int, CaseIterable {
    /// 自由实验：先观察预览，再直接调整场景与参数。
    case freeform
    /// 引导实验：按场景提示操作，将预览与重点参数集中展示。
    case guided

    /// 首次打开和重置时使用的状态；引导实验从顶部前缘对齐开始。
    var initialState: FrameLabState {
        var state = FrameLabState()
        if self == .guided {
            state.scenario = .alignment
            state.option = 0
            state.alignmentIndex = 0
            state.containerHeight = 180
        }
        return state
    }
}

/// 在固定模式切换区下展示当前页面，并保留另一页面的独立实验状态。
final class FrameLabViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.frame.title" }
    // 页面随控制器存活；切换只改变挂载页面，不重新创建组件或实验状态。
    private let pages = FrameLabPresentation.allCases.map { FrameLabView(presentation: $0) }
    private(set) var presentation: FrameLabPresentation = .freeform
    let presentationControl = UISegmentedControl(items: ["", ""])
    var contentView: FrameLabView { pages[presentation.rawValue] }

    override var body: Layout {
        VStack(spacing: 0) {
            presentationControl.resizable().frame(height: 44)
                .safeAreaPadding(.horizontal, 16).padding(.vertical, 8)
            contentView.resizable()
        }.safeAreaPadding(.top, 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        presentationControl.accessibilityIdentifier = "frame.presentation"
        presentationControl.selectedSegmentTintColor = .systemBlue
        presentationControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        presentationControl.selectedSegmentIndex = presentation.rawValue
        presentationControl.addTarget(self, action: #selector(presentationChanged), for: .valueChanged)
        installResetButton()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        for page in pages { page.reloadLocalizedContent() }
        presentationControl.setTitle(Localization.text("frame.presentation.freeform"), forSegmentAt: 0)
        presentationControl.setTitle(Localization.text("frame.presentation.guided"), forSegmentAt: 1)
        presentationControl.accessibilityLabel = Localization.text("frame.presentation.label")
        installResetButton()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        for page in pages { page.reloadLayoutDirection(direction) }
    }

    /// 保存离开页面的位置，在新页面完成布局后恢复其已保存的滚动位置。
    func selectPresentation(_ next: FrameLabPresentation) {
        guard presentation != next else { return }
        contentView.saveScrollPosition()
        presentation = next
        presentationControl.selectedSegmentIndex = next.rawValue
        contentView.prepareScrollRestoration()
        setNeedsQuickLayout()
        quickLayoutIfNeeded()
    }

    @objc private func presentationChanged() {
        guard let next = FrameLabPresentation(rawValue: presentationControl.selectedSegmentIndex) else { return }
        selectPresentation(next)
    }

    private func installResetButton() {
        // 重置与工程原有的语言菜单共存；语言刷新后重新安装按钮组。
        let language = navigationItem.rightBarButtonItems?.first {
            $0.menu != nil
        } ?? navigationItem.leftBarButtonItems?.first {
            $0.menu != nil
        }
        language?.menu = Localization.languageMenu()
        language?.accessibilityLabel = Localization.text("language.menu.accessibility")
        let reset = UIBarButtonItem(image: UIImage(systemName: "arrow.counterclockwise"),
                                    style: .plain, target: self, action: #selector(resetExperiment))
        reset.accessibilityIdentifier = "frame.reset"
        reset.accessibilityLabel = Localization.text("frame.reset")
        reset.tintColor = .systemBlue
        language?.tintColor = .systemBlue
        navigationItem.setBarButtonItems([reset] + (language.map { [$0] } ?? []), side: .trailing)
    }

    /// 只重置当前模式，另一模式的参数、展开状态与滚动位置保持不变。
    @objc func resetExperiment() { contentView.reset() }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Frame · 自由实验") { UINavigationController(rootViewController: FrameLabViewController()) }

@available(iOS 17.0, *)
#Preview("Frame · 引导实验") {
    let page = FrameLabViewController()
    page.loadViewIfNeeded()
    page.selectPresentation(.guided)
    page.contentView.selectScenario(.alignment)
    page.contentView.selectAlignment(0)
    return UINavigationController(rootViewController: page)
}

@available(iOS 17.0, *)
#Preview("Frame · 深色") {
    let controller = UINavigationController(rootViewController: FrameLabViewController())
    controller.overrideUserInterfaceStyle = .dark
    return controller
}

@available(iOS 17.0, *)
#Preview("Frame · RTL") {
    let page = FrameLabViewController()
    page.loadViewIfNeeded()
    page.contentView.selectScenario(.alignment)
    page.contentView.selectAlignment(0)
    page.reloadLayoutDirection(.rightToLeft)
    return UINavigationController(rootViewController: page)
}
#endif
