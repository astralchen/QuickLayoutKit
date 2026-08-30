//
//  LiveRoomRechargeViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomRechargeViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "liveRoom.recharge.page.title" }

    var balanceDidRecharge: ((Int) -> Int?)?

    let viewModel: LiveRoomRechargeViewModel
    let initialRequiredBalance: Int
    let rechargeView = LiveRoomRechargeView(frame: .zero)

    var currentBalance: Int { viewModel.currentBalance }
    var selectedPackageAmount: Int { viewModel.selectedPackageAmount }
    var rechargeSuccessAnimationCount: Int {
        rechargeView.successAnimationCount
    }
    var rechargeStatusText: String? { rechargeView.statusText }
    var isRechargeSuccessAnimationVisible: Bool {
        rechargeView.isSuccessAnimationVisible
    }

    init(currentBalance: Int, requiredBalance: Int) {
        viewModel = LiveRoomRechargeViewModel(
            currentBalance: currentBalance,
            requiredBalance: requiredBalance
        )
        initialRequiredBalance = max(0, requiredBalance)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = LiveRoomRechargeViewModel(
            currentBalance: 0,
            requiredBalance: 0
        )
        initialRequiredBalance = 0
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        updateContent()
    }

    override var body: Layout {
        rechargeView.resizable()
    }

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

    func selectPackage(_ package: LiveRoomRechargePackage) {
        guard viewModel.selectPackage(amount: package.amount) else { return }
        rechargeView.clearStatus()
        updateContent()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func performRecharge() {
        guard let balanceDidRecharge,
            let transaction = viewModel.performRecharge(
                balanceDidRecharge: balanceDidRecharge
            )
        else {
            rechargeView.showFailureStatus(
                DemoLocalization.text("liveRoom.recharge.failure")
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        rechargeView.showSuccessStatus(
            DemoLocalization.text(
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

    func updateContent(preservingStatus: Bool = false) {
        let creditedAmount = viewModel.selectedPackage?.creditedAmount ?? 0
        rechargeView.configure(
            balanceCaption: DemoLocalization.text(
                "liveRoom.recharge.balance.title"
            ),
            balanceText: DemoLocalization.text(
                "liveRoom.recharge.balance.value",
                currentBalance
            ),
            requirementText: DemoLocalization.text(
                "liveRoom.recharge.required",
                initialRequiredBalance
            ),
            packageTitle: DemoLocalization.text(
                "liveRoom.recharge.package.title"
            ),
            packages: viewModel.packages,
            selectedPackageAmount: selectedPackageAmount,
            rechargeTitle: DemoLocalization.text(
                "liveRoom.recharge.confirm",
                creditedAmount
            ),
            preservesStatus: preservingStatus
        )
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargeControllerPreview() -> UIViewController {
    var balance = 1_280
    let viewController = LiveRoomRechargeViewController(
        currentBalance: balance,
        requiredBalance: 8_888
    )
    viewController.balanceDidRecharge = { amount in
        balance += amount
        return balance
    }
    return UINavigationController(rootViewController: viewController)
}

#Preview("充值中心") {
    makeLiveRoomRechargeControllerPreview()
}
#endif
