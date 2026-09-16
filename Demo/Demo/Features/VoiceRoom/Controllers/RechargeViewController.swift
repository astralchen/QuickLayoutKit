//
//  RechargeViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 协调充值档位选择、余额确认和成功动画的控制器。
final class RechargeViewController: LocalizedQuickLayoutHostingController {

    /// 导航标题使用的本地化资源键。
    override var localizedTitleKey: String? { "liveRoom.recharge.page.title" }

    /// 确认充值入账的业务回调；传入金币增量，返回最新余额或 `nil`。
    var balanceDidRecharge: ((Int) -> Int?)?

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: RechargeViewModel
    /// 进入充值页时需要满足的目标金币余额。
    let initialRequiredBalance: Int
    /// 显示充值档位、余额和成功反馈的内容视图。
    let rechargeView = RechargeView(frame: .zero)

    /// 业务层确认的当前金币余额。
    var currentBalance: Int { viewModel.currentBalance }
    /// 当前选中档位的基础金币数。
    var selectedPackageAmount: Int { viewModel.selectedPackageAmount }
    /// 本次页面生命周期内启动的充值成功动画次数。
    var rechargeSuccessAnimationCount: Int {
        rechargeView.successAnimationCount
    }
    /// 当前充值状态提示的显示文案。
    var rechargeStatusText: String? { rechargeView.statusText }
    /// 一个布尔值，指示充值成功反馈是否仍在显示。
    var isRechargeSuccessAnimationVisible: Bool {
        rechargeView.isSuccessAnimationVisible
    }

    /// 使用当前余额和目标余额创建充值页，并解析默认充值档位。
    init(currentBalance: Int, requiredBalance: Int) {
        viewModel = RechargeViewModel(
            currentBalance: currentBalance,
            requiredBalance: requiredBalance
        )
        initialRequiredBalance = max(0, requiredBalance)
        super.init(nibName: nil, bundle: nil)
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        viewModel = RechargeViewModel(
            currentBalance: 0,
            requiredBalance: 0
        )
        initialRequiredBalance = 0
        super.init(coder: coder)
    }

    /// 在视图加载后配置界面并连接内容与交互。
    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        updateContent()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        rechargeView.resizable()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    func configureViews() {
        view.accessibilityIdentifier = "liveRoom.recharge.page"
        rechargeView.bindActions(
            packageDidSelect: { [weak self] package in
                self?.selectPackage(package)
            },
            rechargeDidTap: { [weak self] in
                self?.performRecharge()
            }
        )
        updateContent()
    }

    /// 更新选中的充值档位并刷新页面文案。
    func selectPackage(_ package: RechargePackage) {
        guard viewModel.selectPackage(amount: package.amount) else { return }
        rechargeView.clearStatus()
        updateContent()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 请求业务层确认入账，成功后更新页面并播放余额增长反馈。
    func performRecharge() {
        guard let balanceDidRecharge,
            let transaction = viewModel.performRecharge(
                balanceDidRecharge: balanceDidRecharge
            )
        else {
            rechargeView.showFailureStatus(
                Localization.text("liveRoom.recharge.failure")
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        rechargeView.showSuccessStatus(
            Localization.text(
                "liveRoom.recharge.success",
                transaction.creditedAmount
            )
        )
        updateContent(preservingStatus: true)
        rechargeView.playSuccessAnimation(
            from: transaction.previousBalance,
            to: transaction.updatedBalance,
            creditedAmount: transaction.creditedAmount
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: rechargeView.statusText
        )
    }

    /// 根据已确认余额和所选档位更新页面，可保留已有状态提示。
    func updateContent(preservingStatus: Bool = false) {
        let creditedAmount = viewModel.selectedPackage?.creditedAmount ?? 0
        rechargeView.configure(
            balanceCaption: Localization.text(
                "liveRoom.recharge.balance.title"
            ),
            balanceText: Localization.text(
                "liveRoom.recharge.balance.value",
                currentBalance
            ),
            requirementText: Localization.text(
                "liveRoom.recharge.required",
                initialRequiredBalance
            ),
            packageTitle: Localization.text(
                "liveRoom.recharge.package.title"
            ),
            packages: viewModel.packages,
            selectedPackageAmount: selectedPackageAmount,
            rechargeTitle: Localization.text(
                "liveRoom.recharge.confirm",
                creditedAmount
            ),
            preservesStatus: preservingStatus
        )
    }
}

#if DEBUG
/// 创建展示充值控制器的预览控制器。
@MainActor
private func makeRechargeControllerPreview() -> UIViewController {
    var balance = 1_280
    let viewController = RechargeViewController(
        currentBalance: balance,
        requiredBalance: 8_888
    )
    viewController.balanceDidRecharge = { amount in
        balance += amount
        return balance
    }
    return UINavigationController(rootViewController: viewController)
}

@available(iOS 17.0, *)
#Preview("充值中心") {
    makeRechargeControllerPreview()
}
#endif
