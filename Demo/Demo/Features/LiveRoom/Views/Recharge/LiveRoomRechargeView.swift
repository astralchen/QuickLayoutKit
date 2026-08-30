//
//  LiveRoomRechargeView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值页根视图。
///
/// 根视图只组装背景、滚动内容和成功浮层，并通过语义方法向控制器隐藏具体的
/// UILabel、按钮及卡片层级。
final class LiveRoomRechargeView: QuickLayoutView {

    let backgroundView = QuickLayoutLinearGradientView(
        stops: [
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.13, green: 0.06, blue: 0.28, alpha: 1),
                location: 0
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.08, green: 0.10, blue: 0.27, alpha: 1),
                location: 0.56
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.03, green: 0.19, blue: 0.38, alpha: 1),
                location: 1
            ),
        ],
        startPoint: UnitPoint(x: 0.10, y: 0),
        endPoint: UnitPoint(x: 0.92, y: 1)
    )
    let scrollView = QuickLayoutScrollView(.vertical)
    let contentView = LiveRoomRechargeContentView(frame: .zero)
    let successOverlayView = LiveRoomRechargeSuccessView(frame: .zero)

    var packageDidSelect: ((LiveRoomRechargePackage) -> Void)?
    var rechargeDidTap: (() -> Void)?

    var statusText: String? { contentView.footerView.statusText }
    var isSuccessAnimationVisible: Bool { !successOverlayView.isHidden }
    var successAnimationCount = 0

    var balanceDisplayLink: CADisplayLink?
    var balanceAnimationStartTime: CFTimeInterval = 0
    var balanceAnimationFrom = 0
    var balanceAnimationTo = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    deinit {
        balanceDisplayLink?.invalidate()
    }

    override var body: Layout {
        ZStack {
            backgroundView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            ScrollView(scrollView, .vertical) {
                contentView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)
            }
            // 仅背景延伸到全屏；充值内容仍避开导航栏、刘海和底部安全区。
            .safeAreaPadding(.all, 0)

            successOverlayView
                .resizable()
                .frame(width: 238, height: 162)
        }
    }

    func bindActions(
        packageDidSelect: @escaping (LiveRoomRechargePackage) -> Void,
        rechargeDidTap: @escaping () -> Void
    ) {
        self.packageDidSelect = packageDidSelect
        self.rechargeDidTap = rechargeDidTap
    }

    func configure(
        balanceCaption: String,
        balanceText: String,
        requirementText: String,
        packageTitle: String,
        packages: [LiveRoomRechargePackage],
        selectedPackageAmount: Int,
        rechargeTitle: String,
        preservesStatus: Bool
    ) {
        contentView.balanceCardView.configure(
            caption: balanceCaption,
            balance: balanceText,
            requirement: requirementText
        )
        contentView.packageSectionView.configure(
            title: packageTitle,
            packages: packages,
            selectedAmount: selectedPackageAmount
        )
        contentView.footerView.configureRechargeButton(title: rechargeTitle)
        if !preservesStatus {
            contentView.footerView.setStatus(
                statusText,
                color: UIColor.white.withAlphaComponent(0.68)
            )
        }
        setNeedsQuickLayout()
    }

    func clearStatus() {
        contentView.footerView.setStatus(
            nil,
            color: UIColor.white.withAlphaComponent(0.68)
        )
    }

    func showFailureStatus(_ text: String) {
        contentView.footerView.setStatus(text, color: .systemPink)
    }

    func showSuccessStatus(_ text: String) {
        contentView.footerView.setStatus(text, color: .systemGreen)
    }

    private func configureViews() {
        accessibilityIdentifier = "liveRoom.recharge.page"
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        contentView.packageSectionView.packageDidSelect = { [weak self] package in
            self?.packageDidSelect?(package)
        }
        contentView.footerView.rechargeDidTap = { [weak self] in
            self?.rechargeDidTap?()
        }

        successOverlayView.isHidden = true
        successOverlayView.alpha = 0
        successOverlayView.accessibilityIdentifier =
            "liveRoom.recharge.successOverlay"
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargeViewPreview() -> UIViewController {
    let view = LiveRoomRechargeView(frame: .zero)
    view.bindActions(packageDidSelect: { _ in }, rechargeDidTap: {})
    view.configure(
        balanceCaption: "当前余额",
        balanceText: "12,048 星币",
        requirementText: "本次赠送需余额 88,888",
        packageTitle: "选择充值档位",
        packages: LiveRoomRechargePackage.catalog,
        selectedPackageAmount: 12_800,
        rechargeTitle: "充值 13,600 星币",
        preservesStatus: false
    )
    return QuickLayoutHostingController {
        view
            .resizable()
    }
}

#Preview("充值根视图") {
    makeLiveRoomRechargeViewPreview()
}
#endif
